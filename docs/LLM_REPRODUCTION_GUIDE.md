# NoSleepApp — LLM Reproduction & Re-Engineering Guide

This guide is designed for an AI model or developer to reproduce, compile, package, and verify **NoSleepApp** completely from scratch without external guidance.

---

## 1. Project Requirements & Dependencies

- **Target OS**: macOS 12.0 Monterey or later (Apple Silicon M1/M2/M3/M4 and Intel x86_64).
- **Third-Party Dependencies**: **None (0)**. Pure native Apple frameworks:
  - `SwiftUI` (Declarative user interface)
  - `AppKit` (`NSStatusItem`, `NSPopover`, `NSWindow`, `NSAppleScript`)
  - `CoreGraphics` (`CGMainDisplayID`, `CGDirectDisplayID`)
  - `Foundation` (Process execution, Timers, Pipes)
  - `IOKit.ps` (Native Apple power sources & battery monitoring)
  - `DisplayServices.framework` (Dynamically loaded private framework for display backlight control)

---

## 2. File Tree Structure

```
NoSleepApp/
├── NoSleepApp.swift             # Complete application source code
├── build_app.sh                 # App bundle compiler & packaging script
├── install.sh                   # System-wide 1-click installer to /Applications
├── uninstall.sh                 # Clean uninstaller & permission remover
├── Setup_Passwordless_Mode.command # Standalone double-clickable sudoers setup
├── nosleep.sh                   # Standalone CLI alternative
├── AppIcon.icns                 # macOS application icon bundle
├── README.md                    # User guide & feature overview
├── ARCHITECTURE.md              # Technical architecture & subsystem mechanics
├── DESIGN_SPEC.md               # UI/UX design tokens & typography specification
└── LLM_REPRODUCTION_GUIDE.md    # This reproduction blueprint
```

---

## 3. Step-by-Step Implementation Instructions

### Step 1: Write `NoSleepApp.swift`
Ensure the file contains the following components in sequence:
1. **Dynamic Display Services Bridge**:
   Load `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices` via `dlopen`. Bind `DisplayServicesGetBrightness` and `DisplayServicesSetBrightness`. Save the initial brightness float to a memory variable and `~/.original_brightness`.
2. **`AppState` Observable Object**:
   - Manages state: `isActive`, `remainingSeconds`, `selectedPresetHours`, `isDemoActive`, `demoPhase`, `demoCountdown`, `batteryPercent`, `isACPower`.
   - Native `IOKit.ps` monitoring: Call `IOPSCopyPowerSourcesInfo` and register `IOPSNotificationCreateRunLoopSource` on `CFRunLoopGetMain()`. Add a 1.5s heartbeat timer.
   - Sudo execution: Execute `/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1/0`. If it fails with code 1, automatically prompt once via `NSAppleScript(source: "... with administrator privileges")` to write `/etc/sudoers.d/nosleepapp`.
   - Auto-off timer: Countdown every second. Trigger `turnOff` when remaining seconds reach 0 or if battery drops $\le 20\%$ on battery power.
3. **`DemoOverlayView`**:
   - Centered HUD (`500x340pt`).
   - Plain English copy adhering to George Orwell's 6 rules.
   - Background: `RoundedRectangle(cornerRadius: 20, style: .continuous)`.
   - `.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))`.
   - **Do not use SwiftUI `.shadow()`** (causes square window corner clipping).
4. **`DemoOverlayController`**:
   - Creates a borderless `NSWindow`.
   - Configures hosting controller: `view.wantsLayer = true`, `view.layer?.cornerRadius = 20`, `view.layer?.masksToBounds = true`.
   - Sets window level: `win.level = NSWindow.Level(rawValue: 200)` (floats above popovers).
   - Positions mathematically on `screen.visibleFrame` midpoint.
   - Calls `win.invalidateShadow()`, `win.orderFrontRegardless()`, `NSApp.activate(ignoringOtherApps: true)`.
5. **`PopoverContentView`**:
   - Width `280pt`.
   - Header with `(i)` info toggle for `InfoGuideView`.
   - Digital countdown, presets, Call-to-Action button (`ENABLE NO SLEEP (5H)`).
   - 2-row safeguards card (`Screen when closed` → `Turns off (0%)`, `Power` → `\(battery)% • Plugged in / Battery`).
6. **`AppDelegate`**:
   - Creates `NSStatusItem.squareLength`.
   - Renders 18x18 template moon icon when idle, and procedurally draws an emerald green badge with a lightning bolt when active.
   - Configures `NSPopover` with transient behavior.
   - Hooks up `state.onRequestClosePopover` to automatically dismiss popover when the demo modal opens.

---

### Step 2: Write `build_app.sh`
The build script must:
1. Compile the Swift binary with optimizations and framework links:
   ```bash
   swiftc -O -framework SwiftUI -framework AppKit -framework IOKit -framework CoreGraphics \
       NoSleepApp.swift -o NoSleepApp_bin
   ```
2. Build the standard macOS bundle layout:
   ```bash
   mkdir -p "NoSleepApp.app/Contents/MacOS"
   mkdir -p "NoSleepApp.app/Contents/Resources"
   mv NoSleepApp_bin "NoSleepApp.app/Contents/MacOS/NoSleepApp"
   chmod +x "NoSleepApp.app/Contents/MacOS/NoSleepApp"
   ```
3. Generate `Contents/Info.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>CFBundleExecutable</key>
       <string>NoSleepApp</string>
       <key>CFBundleIdentifier</key>
       <string>com.nosleepapp.mac</string>
       <key>CFBundleName</key>
       <string>NoSleepApp</string>
       <key>CFBundlePackageType</key>
       <string>APPL</string>
       <key>CFBundleShortVersionString</key>
       <string>2.0.0</string>
       <key>CFBundleIconFile</key>
       <string>AppIcon</string>
       <key>LSUIElement</key>
       <true/>
       <key>NSHighResolutionCapable</key>
       <true/>
   </dict>
   </plist>
   ```
   *(Note: `LSUIElement = true` ensures it acts purely as a menu bar accessory with no dock icon).*
4. Copy `AppIcon.icns` into `NoSleepApp.app/Contents/Resources/`.
5. Ad-hoc code sign the bundle:
   ```bash
   codesign --force --deep --sign - "NoSleepApp.app"
   ```

---

### Step 3: Write `Setup_Passwordless_Mode.command`
This script configures the passwordless sudoers entry:
```bash
#!/bin/bash
USER_NAME=$(whoami)
RULE="$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"

sudo mkdir -p /etc/sudoers.d
echo "$RULE" | sudo tee /etc/sudoers.d/nosleepapp > /dev/null
sudo chmod 0440 /etc/sudoers.d/nosleepapp
sudo visudo -c -f /etc/sudoers.d/nosleepapp
```

---

### Step 4: Verification & Testing Playbook

When reproducing this project, execute these verification checks:

1. **Compilation Test**:
   ```bash
   ./build_app.sh
   # Expected exit code: 0
   ```
2. **Launch Test**:
   ```bash
   open NoSleepApp.app
   # Confirm process is active:
   ps aux | grep -i NoSleepApp | grep -v grep
   ```
3. **Power Status Test**:
   - Look at the popover's `Power` row.
   - Disconnect charger $\rightarrow$ Status changes to `On Battery` (Orange).
   - Reconnect charger $\rightarrow$ Status changes to `Plugged in` (Green).
4. **Sleep Prevention Test**:
   - Click `ENABLE NO SLEEP (5H)`.
   - Run `pmset -g | grep SleepDisabled`.
   - Output must be: `SleepDisabled 1`.
   - Screen backlight must be at `0%`.
   - Click `DISABLE NO SLEEP`.
   - Output of `pmset -g` must show `SleepDisabled 0` and previous brightness is restored.
5. **Demo Modal Verification**:
   - Click `Test Screen (10s)`.
   - Confirm popover closes immediately.
   - Confirm modal appears front-and-center with smooth rounded corners (zero square edges).
   - Phase 1 runs for 10 seconds $\rightarrow$ Phase 2 dims screen to 5% preview for 5 seconds $\rightarrow$ Phase 3 auto-restores brightness and dismisses.
