import SwiftUI
import AppKit
import CoreGraphics
import Foundation
import IOKit.ps
import Darwin

// MARK: - Native Display Brightness (via private DisplayServices.framework)
typealias DisplayServicesGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias DisplayServicesSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

final class BrightnessManager {
    static let shared = BrightnessManager()
    private var getBrightnessFn: DisplayServicesGetBrightnessFn?
    private var setBrightnessFn: DisplayServicesSetBrightnessFn?

    var isAvailable: Bool {
        return getBrightnessFn != nil && setBrightnessFn != nil
    }

    init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
                getBrightnessFn = unsafeBitCast(sym, to: DisplayServicesGetBrightnessFn.self)
            }
            if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
                setBrightnessFn = unsafeBitCast(sym, to: DisplayServicesSetBrightnessFn.self)
            }
        }
    }

    func getCurrent() -> Float {
        var b: Float = 0.5
        if let fn = getBrightnessFn {
            _ = fn(CGMainDisplayID(), &b)
        }
        return b
    }

    func set(_ value: Float) {
        guard let fn = setBrightnessFn else { return }
        let clamped = max(0.0, min(1.0, value))
        _ = fn(CGMainDisplayID(), clamped)
    }
}

// MARK: - Persistent State Model for Stale-Crash Reconciliation
struct PersistedSessionState: Codable {
    var isActive: Bool
    var pid: Int32
    var startTime: TimeInterval
    var totalDurationSeconds: Int
    var priorSleepDisabled: Int
    var originalBrightness: Float
}

// MARK: - Visual Effect View for Translucent macOS HUDs
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - App State & Controller
final class AppState: ObservableObject {
    @Published var isActive: Bool = false
    @Published var isBusy: Bool = false
    @Published var remainingSeconds: Int = 5 * 3600
    @Published var totalDurationSeconds: Int = 5 * 3600
    @Published var selectedPresetHours: Double = 5.0

    @Published var dimScreenEnabled: Bool = UserDefaults.standard.object(forKey: "dimScreenEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dimScreenEnabled, forKey: "dimScreenEnabled") }
    }
    @Published var batteryGuardEnabled: Bool = UserDefaults.standard.object(forKey: "batteryGuardEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(batteryGuardEnabled, forKey: "batteryGuardEnabled") }
    }

    @Published var hasBattery: Bool = true
    @Published var batteryPercent: Int = 100
    @Published var isACPower: Bool = true

    @Published var originalBrightness: Float = 0.5
    @Published var statusMessage: String = "Ready"

    // Demo Mode State (Strictly isolated from active session)
    @Published var isDemoActive: Bool = false
    @Published var demoPhase: Int = 1 // 1 = 10s reading notice, 2 = 5s live demo, 3 = finished
    @Published var demoCountdown: Int = 10
    private var demoOriginalBrightness: Float = 0.5

    private var timer: Timer?
    private var demoTimer: Timer?
    private var powerHeartbeatTimer: Timer?
    private var powerRunLoopSource: CFRunLoopSource?
    private var statusItem: NSStatusItem?
    var demoOverlayController: DemoOverlayController?
    var onRequestClosePopover: (() -> Void)?

    private var stateFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nosleepapp_state.json")
    }

    init() {
        self.originalBrightness = BrightnessManager.shared.getCurrent()
        refreshBatteryInfo()
        startPowerMonitoring()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.reconcileStaleSystemSleep()
        }
    }

    // MARK: - Stale State Reconciliation (Fixes Crash/Kill Stuck State)
    private func reconcileStaleSystemSleep() {
        let isSystemDisabled = checkSystemSleepDisabled()
        let saved = loadPersistedState()

        if isSystemDisabled {
            // Only auto-restore when a state file proves our ownership of an active session
            guard let s = saved, s.isActive else {
                // Sleep was disabled manually by the user or another tool outside NoSleepApp
                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = "Sleep disabled externally"
                }
                return
            }

            // Check if recorded PID is still alive
            if s.pid == ProcessInfo.processInfo.processIdentifier || kill(s.pid, 0) == 0 {
                // Currently running instance owns the session
                return
            }

            // Stale disablesleep 1 from a previous crash or kill -9!
            // Only auto-restore silently if passwordless sudo succeeds; do NOT pop an unprompted modal on launch!
            let success = executePasswordlessPmset(disableSleep: false)
            if success {
                clearPersistedState()
                if s.originalBrightness > 0 && BrightnessManager.shared.isAvailable {
                    BrightnessManager.shared.set(s.originalBrightness)
                }
                sendNotification(
                    title: "🛡️ Sleep Settings Reconciled",
                    body: "Recovered from an interrupted session. System sleep has been restored to normal."
                )
            } else {
                // Passwordless sudo failed — surface status rather than popping an unprompted password dialog
                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = "Previous session was interrupted"
                }
                sendNotification(
                    title: "⚠️ Sleep Still Disabled",
                    body: "A previous NoSleepApp session was interrupted. Click the menu bar icon to restore normal sleep."
                )
            }
        } else {
            clearPersistedState()
        }
    }

    private func savePersistedState(active: Bool, priorSleep: Int = 0) {
        let state = PersistedSessionState(
            isActive: active,
            pid: ProcessInfo.processInfo.processIdentifier,
            startTime: Date().timeIntervalSince1970,
            totalDurationSeconds: totalDurationSeconds,
            priorSleepDisabled: priorSleep,
            originalBrightness: originalBrightness
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }

    private func loadPersistedState() -> PersistedSessionState? {
        guard let data = try? Data(contentsOf: stateFileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedSessionState.self, from: data)
    }

    private func clearPersistedState() {
        try? FileManager.default.removeItem(at: stateFileURL)
    }

    func setStatusItem(_ item: NSStatusItem) {
        self.statusItem = item
        updateMenuBarDisplay()
    }

    func updateMenuBarDisplay() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let item = self.statusItem else { return }
            item.button?.title = ""

            if self.isActive {
                item.button?.image = self.renderActiveIcon()
                let h = self.remainingSeconds / 3600
                let m = (self.remainingSeconds % 3600) / 60
                let s = self.remainingSeconds % 60
                item.button?.toolTip = String(format: "NoSleepApp: Active (%02d:%02d:%02d remaining)", h, m, s)
            } else {
                let img = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: "NoSleepApp Idle")
                img?.isTemplate = true
                item.button?.image = img
                item.button?.toolTip = "NoSleepApp: Inactive (Normal Mac Sleep)"
            }
        }
    }

    private func renderActiveIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: 9, y: 9)
        let radius: CGFloat = 6.8

        // 1. Muted circular track
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        trackPath.lineWidth = 1.8
        NSColor(red: 0.08, green: 0.78, blue: 0.45, alpha: 0.28).setStroke()
        trackPath.stroke()

        // 2. Dynamic progress arc
        let progress = totalDurationSeconds > 0 ? max(0.02, min(1.0, Double(remainingSeconds) / Double(totalDurationSeconds))) : 1.0
        let startAngle: CGFloat = 90.0
        let endAngle: CGFloat = startAngle - CGFloat(progress * 360.0)

        let progressPath = NSBezierPath()
        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.lineWidth = 1.8
        progressPath.lineCapStyle = .round
        NSColor(red: 0.08, green: 0.78, blue: 0.45, alpha: 1.0).setStroke()
        progressPath.stroke()

        // 3. Center bolt icon
        if let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 7.5, weight: .bold)
            if let configured = symbol.withSymbolConfiguration(config) {
                configured.isTemplate = false
                let boltRect = NSRect(x: 5.2, y: 4.2, width: 7.6, height: 9.6)
                NSColor(red: 0.08, green: 0.78, blue: 0.45, alpha: 1.0).set()
                configured.draw(in: boltRect)
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    func selectPreset(hours: Double) {
        selectedPresetHours = hours
        let newDuration = Int(hours * 3600)
        totalDurationSeconds = newDuration

        if isActive {
            // Live extension while active without sleep-cycle flicker
            remainingSeconds = newDuration
            updateMenuBarDisplay()
            savePersistedState(active: true)
        } else {
            remainingSeconds = newDuration
            updateMenuBarDisplay()
        }
    }

    func extendTimer(by seconds: Int) {
        remainingSeconds = max(60, remainingSeconds + seconds)
        totalDurationSeconds = max(remainingSeconds, totalDurationSeconds + seconds)
        updateMenuBarDisplay()
        if isActive {
            savePersistedState(active: true)
        }
    }

    func toggle() {
        if isActive {
            turnOff(reason: "Manually disabled")
        } else {
            turnOn()
        }
    }

    func turnOn(overrideSeconds: Int? = nil, skipConfirm: Bool = false) {
        if isBusy { return }

        // Destructive action safety confirmation (bypass with Option-click or after first acknowledgement)
        let hasSeenSafetyNotice = UserDefaults.standard.bool(forKey: "hasSeenSafetyNotice")
        let isOptionDown = NSEvent.modifierFlags.contains(.option)
        if !hasSeenSafetyNotice && !isOptionDown && !skipConfirm {
            let alert = NSAlert()
            alert.messageText = "Enable NoSleepApp?"
            alert.informativeText = "Your Mac will remain awake with the lid closed for \(Int(selectedPresetHours)) hours.\n\n• Screen backlight dims to 0% to prevent keyboard heat buildup.\n• Auto-off restores normal sleep after \(Int(selectedPresetHours)) hours or if battery drops below 20%.\n\nTip: Hold ⌥ Option while clicking to skip this notice in future."
            alert.addButton(withTitle: "Enable No-Sleep")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .informational
            let resp = alert.runModal()
            if resp != .alertFirstButtonReturn {
                return
            }
            UserDefaults.standard.set(true, forKey: "hasSeenSafetyNotice")
        }

        let duration = overrideSeconds ?? totalDurationSeconds
        self.remainingSeconds = duration
        self.totalDurationSeconds = duration
        self.isBusy = true
        self.statusMessage = "Authorizing sleep settings..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let currentB = BrightnessManager.shared.getCurrent()
            let priorSleep = self.checkSystemSleepDisabled() ? 1 : 0
            let success = self.executePrivilegedPmset(disableSleep: true)

            DispatchQueue.main.async {
                self.isBusy = false
                if !success {
                    self.statusMessage = "Admin authorization required"
                    NSSound(named: "Basso")?.play()
                    let alert = NSAlert()
                    alert.messageText = "Admin Authorization Required"
                    alert.informativeText = "NoSleepApp needs permission to disable system sleep when the lid is closed.\n\nPlease enter your administrator password when prompted, or run install.sh for permanent 1-click mode."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    return
                }

                self.originalBrightness = currentB
                self.savePersistedState(active: true, priorSleep: priorSleep)

                if self.dimScreenEnabled && BrightnessManager.shared.isAvailable {
                    BrightnessManager.shared.set(0.0)
                }

                self.isActive = true
                self.statusMessage = "Active: Lid sleep blocked"
                self.startCountdownTimer()
                self.updateMenuBarDisplay()

                let hours = duration / 3600
                let mins = (duration % 3600) / 60
                let timeDesc = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
                let brightnessNote = BrightnessManager.shared.isAvailable 
                    ? "Display set to 0% to keep laptop cool." 
                    : "⚠️ Backlight control unavailable on this Mac model; ensure good ventilation."

                self.sendNotification(
                    title: "⚡ NoSleepApp Activated",
                    body: "Mac will stay awake for \(timeDesc). \(brightnessNote)"
                )
            }
        }
    }

    func turnOff(reason: String = "Session finished", synchronous: Bool = false) {
        if isBusy && !isActive && !synchronous { return }
        timer?.invalidate()
        timer = nil

        let saved = loadPersistedState()
        let priorFlag = saved?.priorSleepDisabled == 1
        let origB = originalBrightness
        let shouldRestoreDim = dimScreenEnabled && BrightnessManager.shared.isAvailable

        if synchronous {
            // Immediate synchronous execution for app termination and relocation paths
            _ = executePrivilegedPmset(disableSleep: priorFlag)
            if shouldRestoreDim {
                BrightnessManager.shared.set(origB)
            }
            clearPersistedState()
            isActive = false
            isBusy = false
            statusMessage = "Idle: Normal sleep restored"
            updateMenuBarDisplay()
            return
        }

        isBusy = true
        statusMessage = "Restoring normal sleep..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            _ = self.executePrivilegedPmset(disableSleep: priorFlag)

            DispatchQueue.main.async {
                self.isBusy = false
                if shouldRestoreDim {
                    BrightnessManager.shared.set(origB)
                }
                self.clearPersistedState()

                self.isActive = false
                self.statusMessage = "Idle: Normal sleep restored"
                self.updateMenuBarDisplay()

                NSSound.beep()
                self.sendNotification(
                    title: "💤 NoSleepApp Restored",
                    body: "\(reason). Normal sleep & screen brightness restored."
                )
            }
        }
    }

    // MARK: - 15-Second Isolated Preview Mode
    func startDemo() {
        if isActive {
            sendNotification(title: "Session Active", body: "Please disable the active No-Sleep session before running the preview.")
            return
        }
        if isDemoActive {
            stopDemo(reason: "Demo stopped")
            return
        }

        onRequestClosePopover?()

        isDemoActive = true
        demoPhase = 1
        demoCountdown = 10
        demoOriginalBrightness = BrightnessManager.shared.getCurrent()

        demoOverlayController?.show()

        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.demoPhase == 1 {
                    if self.demoCountdown > 1 {
                        self.demoCountdown -= 1
                    } else {
                        self.demoPhase = 2
                        self.demoCountdown = 5

                        if BrightnessManager.shared.isAvailable {
                            BrightnessManager.shared.set(0.05)
                        }
                    }
                } else if self.demoPhase == 2 {
                    if self.demoCountdown > 1 {
                        self.demoCountdown -= 1
                    } else {
                        self.demoPhase = 3
                        self.demoCountdown = 0
                        self.demoTimer?.invalidate()
                        self.demoTimer = nil

                        if BrightnessManager.shared.isAvailable {
                            BrightnessManager.shared.set(self.demoOriginalBrightness)
                        }

                        NSSound.beep()
                        self.sendNotification(
                            title: "✓ Preview Completed",
                            body: "Normal screen brightness restored."
                        )

                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            self?.stopDemo(reason: "Completed")
                        }
                    }
                }
            }
        }
    }

    func stopDemo(reason: String = "") {
        demoTimer?.invalidate()
        demoTimer = nil
        isDemoActive = false
        demoPhase = 1
        demoCountdown = 10

        if BrightnessManager.shared.isAvailable {
            BrightnessManager.shared.set(demoOriginalBrightness)
        }

        demoOverlayController?.hide()
    }

    private func startCountdownTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                    self.updateMenuBarDisplay()
                } else {
                    self.turnOff(reason: "Auto-off: Safe timer duration completed")
                }
            }
        }
    }

    func startPowerMonitoring() {
        // 1. Instant native IOKit power notification callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx = ctx else { return }
            let appState = Unmanaged<AppState>.fromOpaque(ctx).takeUnretainedValue()
            appState.refreshBatteryInfo()
        }, context)?.takeRetainedValue() {
            powerRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        // 2. Periodic heartbeat timer (1.5s)
        powerHeartbeatTimer?.invalidate()
        powerHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshBatteryInfo()
        }
    }

    func refreshBatteryInfo() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            DispatchQueue.main.async { [weak self] in
                self?.hasBattery = false
                self?.isACPower = true
            }
            return
        }

        var found = false
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any] {
                let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
                let state = desc[kIOPSPowerSourceStateKey] as? String ?? ""
                let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                let isAC = (state == "AC Power") || isCharging

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.hasBattery = true
                    self.batteryPercent = cur
                    self.isACPower = isAC

                    // IMMEDIATE ENFORCEMENT ON BATTERY DROP
                    if self.isActive && self.batteryGuardEnabled && !self.isACPower && self.batteryPercent <= 20 {
                        self.turnOff(reason: "Auto-off: Battery reached \(self.batteryPercent)% on battery power")
                    }
                }
                found = true
                break
            }
        }

        if !found {
            DispatchQueue.main.async { [weak self] in
                self?.hasBattery = false
                self?.isACPower = true
            }
        }
    }

    private func checkSystemSleepDisabled() -> Bool {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g"]
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if let regex = try? NSRegularExpression(pattern: #"(?i)\bSleepDisabled\s+(\d+)\b"#) {
            let nsOut = out as NSString
            if let match = regex.firstMatch(in: out, range: NSRange(location: 0, length: nsOut.length)) {
                let val = nsOut.substring(with: match.range(at: 1))
                return val == "1"
            }
        }
        return false
    }

    private func executePasswordlessPmset(disableSleep: Bool) -> Bool {
        let flag = disableSleep ? "1" : "0"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", flag]
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    private func executePrivilegedPmset(disableSleep: Bool) -> Bool {
        let flag = disableSleep ? "1" : "0"

        // 1. Passwordless non-interactive sudo check
        if executePasswordlessPmset(disableSleep: disableSleep) {
            return true
        }

        // 2. Strict Username Validation for sudoers configuration
        let user = NSUserName()
        let userRegex = try? NSRegularExpression(pattern: "^[a-z_][a-z0-9_.-]{0,31}$")
        let isUserValid = userRegex?.firstMatch(in: user, range: NSRange(location: 0, length: user.utf16.count)) != nil

        guard isUserValid else {
            let simpleCmd = "do shell script \"/usr/bin/pmset -a disablesleep \(flag)\" with administrator privileges"
            if let simpleScript = NSAppleScript(source: simpleCmd) {
                var err: NSDictionary?
                simpleScript.executeAndReturnError(&err)
                return err == nil
            }
            return false
        }

        let rule = "\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let setupAndRunCmd = "mkdir -p /etc/sudoers.d && echo '\(rule)' > /etc/sudoers.d/nosleepapp.tmp && chmod 0440 /etc/sudoers.d/nosleepapp.tmp && chown root:wheel /etc/sudoers.d/nosleepapp.tmp && /usr/sbin/visudo -c -f /etc/sudoers.d/nosleepapp.tmp && mv /etc/sudoers.d/nosleepapp.tmp /etc/sudoers.d/nosleepapp && /usr/bin/pmset -a disablesleep \(flag)"

        let appleScriptSource = "do shell script \"\(setupAndRunCmd)\" with administrator privileges"
        if let appleScript = NSAppleScript(source: appleScriptSource) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error == nil {
                return true
            }
        }

        // Fallback to direct prompt
        let simpleCmd = "do shell script \"/usr/bin/pmset -a disablesleep \(flag)\" with administrator privileges"
        if let simpleScript = NSAppleScript(source: simpleCmd) {
            var err: NSDictionary?
            simpleScript.executeAndReturnError(&err)
            return err == nil
        }

        return false
    }

    private func sendNotification(title: String, body: String) {
        let safeTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let safeBody = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(safeBody)\" with title \"\(safeTitle)\""

        DispatchQueue.global(qos: .userInitiated).async {
            let ascript = NSAppleScript(source: script)
            ascript?.executeAndReturnError(nil)
        }
    }
}

// MARK: - On-Screen Demo HUD View (Written in Plain English via Orwell's Rules)
struct DemoOverlayView: View {
    @ObservedObject var state: AppState
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header Bar with Title and Status Pill
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "display.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text("Screen Dimming Preview")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                // Dynamic Countdown Badge
                Text(state.demoPhase == 1 
                     ? "READ (\(String(format: "%02d", state.demoCountdown))s)" 
                     : (state.demoPhase == 2 
                        ? "TESTING (\(String(format: "%02d", state.demoCountdown))s)" 
                        : "DONE"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        state.demoPhase == 1
                        ? Color.orange.opacity(0.25)
                        : (state.demoPhase == 2 ? Color.green.opacity(0.25) : Color.blue.opacity(0.25))
                    )
                    .foregroundColor(
                        state.demoPhase == 1
                        ? Color.orange
                        : (state.demoPhase == 2 ? Color.green : Color.blue)
                    )
                    .clipShape(Capsule())
            }

            // High-Contrast Explanatory Card (Orwell Plain English)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In this 5-second test:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        Text("The screen dims to 5% so you can still read this text.")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("When you close the lid:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        Text("The screen turns off completely (0%) so it does not heat your laptop.")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )

            // Dynamic Monospace Countdown Display
            VStack(spacing: 4) {
                Text(String(format: "00:%02d", state.demoCountdown))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundColor(
                        state.demoPhase == 1
                        ? Color(red: 1.0, green: 0.75, blue: 0.2)
                        : (state.demoPhase == 2 ? Color.green : Color.white)
                    )

                Text(state.demoPhase == 1 
                     ? "5% dim preview starts in \(state.demoCountdown) seconds..." 
                     : (state.demoPhase == 2 
                        ? "Testing 5% screen brightness. Resetting in \(state.demoCountdown)s..." 
                        : "Done. Normal brightness restored."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
            }
            .padding(.vertical, 2)

            // Manual Close Button
            Button(action: onClose) {
                Text(state.demoPhase == 3 ? "Close Window" : "Stop Preview")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(20)
        .frame(width: 500, height: 340)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - On-Screen Pop-up Window Controller (Non-Aggressive Floating Window)
final class DemoOverlayController {
    private var window: NSWindow?
    private let state: AppState

    init(state: AppState) {
        self.state = state
    }

    func show() {
        let winWidth: CGFloat = 500
        let winHeight: CGFloat = 340

        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: winWidth, height: winHeight),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating
            win.isMovableByWindowBackground = true
            win.hasShadow = true

            let hosting = NSHostingController(
                rootView: DemoOverlayView(state: state, onClose: { [weak self] in
                    self?.state.stopDemo(reason: "Dismissed by user")
                })
            )
            hosting.view.wantsLayer = true
            hosting.view.layer?.cornerRadius = 20
            hosting.view.layer?.masksToBounds = true

            win.contentViewController = hosting
            self.window = win
        }

        // Center on active display without stealing keyboard focus
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.origin.x + (screenFrame.width - winWidth) / 2.0
            let y = screenFrame.origin.y + (screenFrame.height - winHeight) / 2.0
            window?.setFrame(NSRect(x: x, y: y, width: winWidth, height: winHeight), display: true)
        }

        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}

// MARK: - Info Guide View (Use Cases in Crisp Plain English)
struct InfoGuideView: View {
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why Use NoSleepApp?")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 7) {
                InfoItem(
                    icon: "sparkles",
                    color: .purple,
                    title: "Run Autonomous AI Agents",
                    desc: "Leave Hermes, Claude, or coding tasks running. Close your lid and move around."
                )

                InfoItem(
                    icon: "network",
                    color: .blue,
                    title: "Remote Access & Control",
                    desc: "SSH or remote control your closed MacBook from your phone or tablet."
                )

                InfoItem(
                    icon: "arrow.down.circle.fill",
                    color: .green,
                    title: "Torrents & Long Downloads",
                    desc: "Complete large file transfers overnight with screen backlight 100% off."
                )

                InfoItem(
                    icon: "shield.checkered",
                    color: .orange,
                    title: "Guaranteed 5h Hardware Safety",
                    desc: "Auto-off prevents heat build-up and shuts off if battery drops below 20%."
                )
            }
            .padding(9)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            Button(action: onBack) {
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                    Text("Back to Controls")
                        .font(.system(size: 11, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.15))
                .foregroundColor(.primary)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

struct InfoItem: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 14, height: 14)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Minimal Professional SwiftUI Popover View
struct PopoverContentView: View {
    @ObservedObject var state: AppState
    @State private var showInfo: Bool = false

    var formattedTime: String {
        let h = state.remainingSeconds / 3600
        let m = (state.remainingSeconds % 3600) / 60
        let s = state.remainingSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header with Accessible Status Pill & (i) Info Toggle
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 15))
                        .foregroundColor(state.isActive ? Color.green : Color.secondary)
                    Text("NoSleepApp")
                        .font(.system(size: 13, weight: .bold))

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showInfo.toggle()
                        }
                    }) {
                        Image(systemName: showInfo ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 13))
                            .foregroundColor(showInfo ? .accentColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Why keep your Mac awake? Click to learn more.")
                }
                Spacer()

                // Accessible Indicator with Icon + Text
                Text(state.isActive ? "● Active" : "○ Idle")
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(state.isActive ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15))
                    .foregroundColor(state.isActive ? Color.green : Color.secondary)
                    .clipShape(Capsule())
            }

            if showInfo {
                InfoGuideView(onBack: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showInfo = false
                    }
                })
            } else {
                // Big Monospace Countdown Display
                VStack(spacing: 2) {
                    Text(formattedTime)
                        .font(.system(size: 32, weight: .medium, design: .monospaced))
                        .foregroundColor(state.isActive ? .primary : .secondary)

                    Text(state.isActive ? "Will stop automatically" : "Stops after \(Int(state.selectedPresetHours)) hours")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)

                // Live Preset Selector (Works Live While Active)
                HStack(spacing: 5) {
                    ForEach([1.0, 2.0, 3.0, 5.0, 8.0], id: \.self) { hours in
                        Button(action: {
                            state.selectPreset(hours: hours)
                        }) {
                            Text("\(Int(hours))h")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    state.selectedPresetHours == hours
                                    ? (state.isActive ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.2))
                                    : Color.secondary.opacity(0.1)
                                )
                                .foregroundColor(
                                    state.selectedPresetHours == hours
                                    ? (state.isActive ? Color.green : Color.accentColor)
                                    : Color.primary
                                )
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(state.isBusy)
                        .help(state.isActive ? "Extend remaining session to \(Int(hours)) hours" : "Set auto-off timer to \(Int(hours)) hours")
                        .accessibilityLabel("Select \(Int(hours)) hours")
                    }
                }

                // Master 1-Click Action Button with Keyboard Shortcut (Cmd + E)
                Button(action: {
                    state.toggle()
                }) {
                    HStack(spacing: 6) {
                        if state.isBusy {
                            ProgressView()
                                .scaleEffect(0.65)
                            Text(state.isActive ? "RESTORING..." : "AUTHORIZING...")
                                .font(.system(size: 12, weight: .bold))
                        } else {
                            Image(systemName: state.isActive ? "stop.fill" : "bolt.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(state.isActive ? "DISABLE NO SLEEP" : "ENABLE NO SLEEP (\(Int(state.selectedPresetHours))H)")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        state.isActive
                        ? Color.red.opacity(0.85)
                        : (state.isBusy ? Color.accentColor.opacity(0.6) : Color.accentColor)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(7)
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(state.isBusy)
                .accessibilityLabel(state.isActive ? "Disable No Sleep" : "Enable No Sleep")
                .help(state.isActive 
                    ? "Disables no-sleep mode, re-enables normal Mac lid-sleep behavior, and restores your original screen brightness immediately." 
                    : "Keeps your MacBook awake with the lid closed for \(Int(state.selectedPresetHours)) hours and dims screen backlight to 0% to prevent heat build-up. Hold ⌥ Option while clicking to skip confirmation.")

                Divider()

                // Interactive Hardware Safeguards & Power Card
                VStack(spacing: 8) {
                    // Row 1: Backlight Dimming Toggle
                    HStack(alignment: .center) {
                        HStack(spacing: 6) {
                            Image(systemName: "display.slash")
                                .font(.system(size: 11))
                                .foregroundColor(.cyan)
                            Text("Dim screen to 0%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        if BrightnessManager.shared.isAvailable {
                            Toggle("", isOn: $state.dimScreenEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: .cyan))
                                .scaleEffect(0.75)
                                .help("Turns off display backlight completely while closed to prevent keyboard heat buildup.")
                        } else {
                            Text("Unavailable")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.orange)
                                .help("DisplayServices brightness control is not supported on this Mac model.")
                        }
                    }

                    // Row 2: Low Battery Guard Toggle
                    HStack(alignment: .center) {
                        HStack(spacing: 6) {
                            Image(systemName: state.isACPower ? "powerplug.fill" : (state.batteryPercent <= 20 ? "battery.0" : "battery.50"))
                                .font(.system(size: 11))
                                .foregroundColor(state.isACPower ? .green : (state.batteryPercent <= 20 ? .red : .orange))
                            Text("Low battery cutoff")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        if state.hasBattery {
                            Toggle("", isOn: $state.batteryGuardEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .scaleEffect(0.75)
                                .help("Stops automatically if unplugged and battery drops below 20%.")
                        } else {
                            Text("Desktop Mac")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    }

                    // Status details footer
                    HStack {
                        Text(state.hasBattery 
                            ? (state.isACPower ? "\(state.batteryPercent)% • Connected to AC Power" : "\(state.batteryPercent)% • On Battery") 
                            : "Desktop Mac • Continuous Power")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                        Spacer()
                        if state.hasBattery && !state.isACPower {
                            Text("Stops at 20%")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(state.batteryPercent <= 20 ? .red : .orange)
                        }
                    }
                }
                .padding(9)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)

                // Footer Controls (Accessible Font Sizes)
                HStack {
                    Button(action: {
                        state.startDemo()
                    }) {
                        Text(state.isDemoActive ? "Stop Preview" : "Preview dimming (15s)")
                            .font(.system(size: 10.5))
                            .foregroundColor(state.isDemoActive ? .red : (state.isActive ? Color.secondary.opacity(0.5) : .secondary))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(state.isActive)
                    .help(state.isActive ? "Stop active No-Sleep session to run the screen preview" : "Shows how screen dimming works, then tests 5% brightness for 5 seconds.")

                    Spacer()

                    Button(action: {
                        if state.isActive {
                            state.turnOff(reason: "App Quit", synchronous: true)
                        }
                        NSApplication.shared.terminate(nil)
                    }) {
                        Text("Quit App")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Completely exits NoSleepApp. Restores normal sleep and screen brightness.")
                }
            }
        }
        .padding(14)
        .frame(width: 285)
        .onAppear {
            state.refreshBatteryInfo()
        }
    }
}

// MARK: - App Delegate & Menu Bar Setup
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let state = AppState()
    private var overlayController: DemoOverlayController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if checkMoveToApplications() {
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        state.setStatusItem(statusItem)

        overlayController = DemoOverlayController(state: state)
        state.demoOverlayController = overlayController

        state.onRequestClosePopover = { [weak self] in
            self?.closePopover()
        }

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 285, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverContentView(state: state))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showPopover()
        }
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    @objc func togglePopover() {
        state.refreshBatteryInfo()
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        state.refreshBatteryInfo()
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Safe Atomic Relocation to /Applications
    @discardableResult
    private func checkMoveToApplications() -> Bool {
        let bundlePath = Bundle.main.bundlePath

        if bundlePath.hasPrefix("/Applications") || bundlePath.hasPrefix("/System/Applications") {
            return false
        }

        let isVolume = bundlePath.hasPrefix("/Volumes/")

        if !isVolume && UserDefaults.standard.bool(forKey: "SuppressMoveToApplicationsPrompt") {
            return false
        }

        // Validate source is a real bundle
        let infoPlist = (bundlePath as NSString).appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlist) else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Move to Applications folder?"
        alert.informativeText = "NoSleepApp works best from your Applications folder. Would you like to move it now?"
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Do Not Move")
        alert.alertStyle = .informational
        alert.window.level = .floating

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if !isVolume {
                UserDefaults.standard.set(true, forKey: "SuppressMoveToApplicationsPrompt")
            }
            return false
        }

        let destPath = "/Applications/NoSleepApp.app"
        let tempPath = "/Applications/NoSleepApp.app.tmp.\(UUID().uuidString)"
        let fileManager = FileManager.default
        var copySuccess = false

        do {
            try fileManager.copyItem(atPath: bundlePath, toPath: tempPath)
            let destURL = URL(fileURLWithPath: destPath)
            let tempURL = URL(fileURLWithPath: tempPath)

            if fileManager.fileExists(atPath: destPath) {
                _ = try? fileManager.replaceItemAt(destURL, withItemAt: tempURL, backupItemName: nil, options: [])
            } else {
                try fileManager.moveItem(at: tempURL, to: destURL)
            }
            copySuccess = true
        } catch {
            _ = try? fileManager.removeItem(atPath: tempPath)
            let appleScriptSrc = bundlePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"rm -rf /Applications/NoSleepApp.app && cp -R \" & quoted form of \"\(appleScriptSrc)\" & \" /Applications/NoSleepApp.app\" with administrator privileges"
            if let appleScript = NSAppleScript(source: script) {
                var errorDict: NSDictionary?
                appleScript.executeAndReturnError(&errorDict)
                if errorDict == nil {
                    copySuccess = true
                }
            }
        }

        guard copySuccess else {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Could not move to Applications"
            errorAlert.informativeText = "Please drag NoSleepApp to your Applications folder manually."
            errorAlert.window.level = .floating
            errorAlert.runModal()
            return false
        }

        if state.isActive {
            state.turnOff(reason: "Relocating to Applications", synchronous: true)
        }

        let openTask = Process()
        openTask.launchPath = "/usr/bin/open"
        openTask.arguments = [destPath]
        try? openTask.run()

        if isVolume {
            let parts = bundlePath.components(separatedBy: "/")
            if parts.count >= 3 {
                let volumePath = "/" + parts[1] + "/" + parts[2]
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    let detachTask = Process()
                    detachTask.launchPath = "/usr/bin/hdiutil"
                    detachTask.arguments = ["detach", volumePath, "-quiet", "-force"]
                    try? detachTask.run()
                }
            }
        }

        exit(0)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if state.isActive {
            state.turnOff(reason: "App terminating", synchronous: true)
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if state.isActive {
            state.turnOff(reason: "App terminating", synchronous: true)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
