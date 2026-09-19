# NoSleepApp — Technical Architecture & Implementation Logic

This document details the complete internal mechanics, system-level APIs, and execution flows of **NoSleepApp**. It provides the exact specifications required for an engineer or LLM to re-implement the application without ambiguity.

---

## 1. System Architecture Overview

```
                      ┌──────────────────────────────────────────────┐
                      │              macOS Status Bar                │
                      │  NSStatusItem (18x18pt Custom Dynamic Icon)  │
                      └──────────────────────┬───────────────────────┘
                                             │ User Click
                                             ▼
                             ┌───────────────────────────────┐
                             │       NSPopover (SwiftUI)     │
                             │   PopoverContentView (280pt)   │
                             └───────────────┬───────────────┘
                                             │
                      ┌──────────────────────┼──────────────────────┐
                      │                      │                      │
                      ▼                      ▼                      ▼
         ┌─────────────────────────┐   ┌───────────────┐   ┌─────────────────┐
         │     AppState Model      │   │  Info Guide   │   │  Demo Overlay   │
         │  (@ObservableObject)    │   │  (Use Cases)  │   │  HUD (500x340)  │
         └────────────┬────────────┘   └───────────────┘   └────────┬────────┘
                      │                                             │
    ┌─────────────────┼─────────────────┬───────────────────────────┤
    │                 │                 │                           │
    ▼                 ▼                 ▼                           ▼
┌──────────────┐ ┌─────────────┐ ┌──────────────┐          ┌────────────────┐
│ Power Engine │ │ Display Mgr │ │ IOKit Battery│          │ Window Level   │
│ (pmset/sudo) │ │(Backlight 0)│ │ (Real-Time)  │          │ (200 / Above)  │
└──────────────┘ └─────────────┘ └──────────────┘          └────────────────┘
```

---

## 2. Core Subsystems & macOS Mechanics

### 2.1 Clamshell Sleep Prevention (`pmset`)
- **Problem**: On modern macOS (especially Apple Silicon M1/M2/M3/M4), standard utilities like `caffeinate -d` or `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep)` only prevent idle sleep when the laptop lid is open or when an external display and power brick are connected. When running on battery without external peripherals, closing the lid forces hardware clamshell sleep.
- **Solution**: The only reliable mechanism to keep a closed laptop awake is setting the system power management parameter:
  ```bash
  /usr/bin/pmset -a disablesleep 1   # Prevents sleep under all conditions, including lid closure
  /usr/bin/pmset -a disablesleep 0   # Restores standard macOS sleep behavior
  ```
- **State Verification**: The app checks `/usr/bin/pmset -g` at startup. If `SleepDisabled 1` is present, it synchronizes its active state automatically.

### 2.2 Permanent Passwordless Operation (`sudoers`)
- **Problem**: Calling `pmset -a disablesleep` requires `root` privileges. Requesting the admin password via AppleScript prompt on every toggle creates unacceptable user friction.
- **Solution**: A strictly scoped, per-user rule is installed into `/etc/sudoers.d/nosleepapp`:
  ```text
  <username> ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
  ```
  - **Security Bound**: Scoped strictly to the specific active `$USER` (validated via regex `^[a-z_][a-z0-9_.-]{0,31}$`). Only the exact commands `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1` are exempted. No other command or argument can be executed without authorization.
  - **Atomic File Security**: Permissions are set to `0440` with ownership `root:wheel`. Staged in `.tmp` and validated with `/usr/sbin/visudo -c -f` before moving into place.
  - **Self-Healing Installation**: When the user first clicks "ENABLE NO SLEEP", if passwordless execution fails, the app prompts for the admin password once via `NSAppleScript` using `with administrator privileges`, writes the sudoers rule atomically, validates it with `visudo`, and re-executes. All subsequent calls bypass password prompts forever.

### 2.3 Native Display Backlight Control (`DisplayServices.framework`)
- **Problem**: Keeping a closed laptop awake with the screen illuminated creates heat between the screen panel and keyboard, and wastes battery.
- **Solution**: Dynamically link macOS private framework `DisplayServices.framework`:
  ```swift
  typealias DisplayServicesGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
  typealias DisplayServicesSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
  ```
  - Loaded via `dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)`.
  - Resolved via `dlsym(handle, "DisplayServicesGetBrightness")` and `dlsym(handle, "DisplayServicesSetBrightness")`.
  - `getCurrent()` queries `CGMainDisplayID()` and stores `originalBrightness` in memory and disk (`~/.original_brightness`).
  - When active: Brightness is set to `0.00` (completely off, zero heat).
  - When turning off or quitting: The stored `originalBrightness` is restored immediately.

### 2.4 Real-Time Power & Battery Monitoring (`IOKit.ps`)
- **Problem**: Spawning child shell processes (`pmset -g batt`) causes high CPU spikes, delayed UI state, and fails to update when the popover is idle.
- **Solution**: Direct C-level integration with macOS `IOKit.ps` (IOPowerSources):
  1. **Query API**:
     ```swift
     let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
     let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
     for ps in list {
         let desc = IOPSGetPowerSourceDescription(blob, ps).takeUnretainedValue() as? [String: Any]
         let capacity = desc[kIOPSCurrentCapacityKey] as? Int
         let state = desc[kIOPSPowerSourceStateKey] as? String // "AC Power" or "Battery Power"
         let isCharging = desc[kIOPSIsChargingKey] as? Bool
     }
     ```
  2. **Event Notification**:
     An event source is added to `CFRunLoopGetMain()` via `IOPSNotificationCreateRunLoopSource(...)`. The callback fires immediately when MagSafe or USB-C is plugged or unplugged.
  3. **Heartbeat Timer**: A 1.5-second background timer acts as a secondary refresh loop.
  4. **Safety Guard**: If on battery (`isACPower == false`) and battery level drops $\le 20\%$, the app automatically turns off no-sleep mode, restores normal sleep, and notifies the user.

---

## 3. UI/UX Architecture & Window Management

### 3.1 Status Item & Dynamic Menu Bar Icon
- Built with `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)`.
- **Idle State**: Template system image `moon.zzz.fill` (18x18pt). Automatically adapts to Dark/Light menu bars.
- **Active State**: Procedurally drawn 18x18pt image using `NSImage` and `lockFocus()`:
  - Base: Circular path filled with Emerald Green (`NSColor(red: 0.06, green: 0.72, blue: 0.51, alpha: 1.0)`).
  - Glyph: White centered lightning bolt (`bolt.fill`).
  - Tooltip: Dynamic countdown string updated every second (`NoSleepApp: Active (04h 58m remaining)`).

### 3.2 Main Popover
- Built with `NSPopover` with `.transient` behavior (auto-closes on outside click).
- Width: `280pt`, Height: `320pt`.
- Root view: `PopoverContentView(state: state)` hosted in `NSHostingController`.
- Contains:
  - Header with `(i)` flip toggle for use-case guide.
  - Large monospace digital countdown (`32pt`, `design: .monospaced`).
  - Horizontal preset duration selector buttons (`1h`, `2h`, `3h`, `5h`, `8h`).
  - Call-To-Action (CTA) Button (`ENABLE NO SLEEP (5H)` / `DISABLE NO SLEEP`).
  - Hardware safeguards status card (Screen closed state + Power source state).
  - Footer controls (`Test Screen (10s)`, `Quit App`).

### 3.3 Centered Floating HUD Window (`DemoOverlayController`)
- **Layering Fix**: To prevent the popover from obscuring the demo HUD:
  1. `state.onRequestClosePopover?()` is called immediately on demo start.
  2. The HUD window level is set to `NSWindow.Level(rawValue: 200)` (higher than `NSWindow.Level.popUpMenu` which is 101).
  3. `win.orderFrontRegardless()` and `NSApp.activate(ignoringOtherApps: true)` are called.
- **Mathematical Centering**:
  Coordinates are calculated using the active screen's visible area:
  $$X = \text{screenFrame.origin.x} + \frac{\text{screenFrame.width} - \text{winWidth}}{2}$$
  $$Y = \text{screenFrame.origin.y} + \frac{\text{screenFrame.height} - \text{winHeight}}{2}$$
- **Zero Square Corners**:
  - The hosting controller's layer has `layer.cornerRadius = 20` and `layer.masksToBounds = true`.
  - SwiftUI root view uses `RoundedRectangle(cornerRadius: 20, style: .continuous)` for background, stroke, and `.clipShape()`.
  - Native window shadowing (`win.hasShadow = true`) paired with `win.invalidateShadow()` ensures WindowServer renders the drop shadow strictly around the 20pt curved path, with no rectangular clipping artifacts.

---

## 4. State Machine & Countdown Engine

```
       ┌───────────┐
       │   IDLE    │◄────────────────────────────────┐
       └─────┬─────┘                                 │
             │ User clicks ENABLE (preset hours)     │ Timer = 0 OR
             ▼                                       │ User clicks DISABLE OR
       ┌───────────┐                                 │ Battery < 20% on DC
       │  ACTIVE   │─────────────────────────────────┘
       │ Backlight │
       │    0%     │
       └───────────┘

   [DEMO MODE STATE MACHINE]
       ┌───────────┐
       │   IDLE    │
       └─────┬─────┘
             │ User clicks "Test Screen (10s)"
             ▼
       ┌───────────────────────────────┐
       │ PHASE 1: Reading Notice (10s) │
       │ Screen = 100% (Normal)        │
       │ Pop-up HUD = Visible (Center) │
       └─────────────┬─────────────────┘
                     │ Countdown = 0
                     ▼
       ┌───────────────────────────────┐
       │ PHASE 2: Live Test (5s)       │
       │ Screen = 5% Preview           │
       │ No-Sleep Active               │
       └─────────────┬─────────────────┘
                     │ Countdown = 0
                     ▼
       ┌───────────────────────────────┐
       │ PHASE 3: Completed            │
       │ Screen & Sleep Restored (100%)│
       │ Auto-dismiss HUD after 2s     │
       └───────────────────────────────┘
---

## 5. Security & Reliability Architecture

NoSleepApp implements defense-in-depth measures to protect Mac hardware, battery health, and system privilege boundaries:

### 1. Crash & Kill Recovery (Stale-State Reconciler)
- **Problem**: `pmset -a disablesleep 1` persists across process death (`kill -9`, kernel panic, ungraceful power loss). If an app dies without resetting it, the Mac never sleeps even when packed into a bag, causing dangerous heat build-up.
- **Solution**: On launch, `reconcileStaleSystemSleep()` inspects `pmset -g` for `SleepDisabled 1` and matches it against `~/.nosleepapp_state.json`. If the recording PID is dead or orphaned, it automatically resets sleep to normal (`pmset -a disablesleep 0`), restores display brightness, and notifies the user.

### 2. Scoped Per-User Privilege Model
- **Problem**: Broad `%admin ALL=(ALL) NOPASSWD` rules grant passwordless root power control to all administrators. Unsanitized username interpolation in shell commands introduces injection vulnerabilities.
- **Defense**:
  - Privilege rules are strictly scoped to `$USER` (per-user only).
  - Usernames are validated against strict regex: `^[a-z_][a-z0-9_.-]{0,31}$`.
  - All sudoers modifications write to a temporary file (`.tmp`), verified via `/usr/sbin/visudo -c -f`, and protected with permissions `0440` and ownership `root:wheel`.

### 3. AppleScript Injection Hardening
- AppleScript string literals dynamically generated for notifications and relocation escape backslashes (`\\`) first, then double quotes (`\"`), preventing script breakout.

### 4. Hardware Safety & Heat Mitigation
- **DisplayServices Availability Guard**: If private `DisplayServices.framework` fails to load, `BrightnessManager.shared.isAvailable` returns `false`. The UI warns "Unavailable" and prompts the user to maintain adequate ventilation.
- **Zero-Latency Battery Guard**: Rather than waiting for timer ticks, power drops below 20% on battery are intercepted immediately in `refreshBatteryInfo()` to restore sleep.
- **Isolated Preview Demo**: The 15-second preview demo maintains dedicated state variables (`demoOriginalBrightness`) and blocks execution while an active session is running to prevent session clobbering.

---

## 6. Evolution & User Feedback Archive

For complete insights into how user feedback, security audits, and bug reports shaped this architecture, refer to the dedicated **`learning_feedback/`** repository:
- [**`learning_feedback/README.md`**](../learning_feedback/README.md): Master index and overview of user guidance.
- [**`learning_feedback/USER_FEEDBACK_ANALYSIS.md`**](../learning_feedback/USER_FEEDBACK_ANALYSIS.md): Technical deep-dive across 5 engineering domains.
- [**`learning_feedback/CHRONOLOGICAL_FEEDBACK_LOG.md`**](../learning_feedback/CHRONOLOGICAL_FEEDBACK_LOG.md): Step-by-step history from initial concept to hardened production release.
- [**`learning_feedback/RULES_AND_BEST_PRACTICES.md`**](../learning_feedback/RULES_AND_BEST_PRACTICES.md): Codified rules for macOS system tools and Orwellian UI copy.
