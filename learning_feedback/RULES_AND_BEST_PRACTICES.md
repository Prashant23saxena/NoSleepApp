# Codified Rules & Best Practices for macOS Systems Development

Derived directly from the user's architectural reviews and feedback on **NoSleepApp**, these rules represent best practices for developing native macOS applications that interact with hardware, power management, and system privileges.

---

## 1. George Orwell's Rules for User Interface Copy

All copy in NoSleepApp adheres to George Orwell's six rules of clear writing (from *Politics and the English Language*):

1. **Never use a metaphor, simile, or other figure of speech which you are used to seeing in print.**
   - *Applied*: Avoid jargon like "prevent sleep assertion", "pmset flag", "IOPMAssertion". Use plain outcomes: "Mac will stay awake", "Lid sleep blocked".
2. **Never use a long word where a short one will do.**
   - *Applied*: Use "turns off" instead of "extinguishes backlight"; use "dims" instead of "attenuates luminosity".
3. **If it is possible to cut a word out, always cut it out.**
   - *Applied*: "Stops after 5 hours" instead of "This session will automatically terminate after an elapsed duration of 5 hours".
4. **Never use the passive where you can use the active.**
   - *Applied*: `ENABLE NO SLEEP (5H)` instead of "No Sleep is Enabled".
5. **Never use a foreign phrase, a scientific word, or a jargon word if you can think of an everyday English equivalent.**
   - *Applied*: "Lid closed" instead of "clamshell mode"; "unplugged" instead of "DC power source state".
6. **Break any of these rules sooner than say anything outright barbarous.**

---

## 2. macOS Privilege & Sudoers Architecture

When an application requires root privileges for system calls (such as `pmset`):

1. **Per-User Scoping Only**:
   - Never use `%admin ALL=(ALL) NOPASSWD`. That grants passwordless power to every administrator account on the system.
   - Always scope specifically to `$USER` or `$CONSOLE_USER`.
2. **Strict Username Sanitization**:
   - Always validate usernames against regex `^[a-z_][a-z0-9_.-]{0,31}$` before shell interpolation or writing to sudoers files.
   - Prevents command injection via single quotes, spaces, or metacharacters.
3. **Atomic `.tmp` + `visudo` Pattern**:
   - Never pipe directly to `/etc/sudoers.d/target`. A malformed line will break `sudo` for the entire system.
   - Flow:
     ```bash
     echo "$RULE" > "/etc/sudoers.d/rule.tmp"
     chmod 0440 "/etc/sudoers.d/rule.tmp"
     chown root:wheel "/etc/sudoers.d/rule.tmp"
     if /usr/sbin/visudo -c -f "/etc/sudoers.d/rule.tmp"; then
         mv "/etc/sudoers.d/rule.tmp" "/etc/sudoers.d/rule"
     else
         rm -f "/etc/sudoers.d/rule.tmp"
     fi
     ```
4. **No Gatekeeper Bypass**:
   - Never instruct users to run `xattr -cr` or embed it in installation scripts.
   - Provide cryptographic SHA-256 verification and clear Gatekeeper approval guidance (Right-Click -> Open).
5. **No Unprompted Launch Modals**:
   - Never prompt for admin credentials during application launch or background startup.
   - Test passwordless execution via `sudo -n`; if it fails, surface an informational banner and await explicit user action.

---

## 3. Hardware Thermal Safety in Laptop Background Workloads

Running closed-lid MacBooks for background workloads (AI coding agents, torrents, batch jobs) introduces critical thermal and battery risks:

1. **Total Display Backlight Shutdown (0%)**:
   - 5% brightness is insufficient under a closed lid; LED backlights trap heat directly against the LCD and keyboard.
   - Use `DisplayServicesSetBrightness(CGMainDisplayID(), 0.0)` to dim backlight completely to 0%.
   - Always verify private framework availability (`dlopen`/`dlsym`). If unavailable, warn the user prominently and recommend ventilation.
2. **Zero-Latency Hardware Cutoff**:
   - Never rely on slow timer polling (e.g. 30 seconds) for battery safety.
   - Bind native `IOPSNotificationCreateRunLoopSource` to receive instant kernel-level power state notifications.
   - If unplugged and battery reaches $\le 20\%$, immediately cancel keepalive assertions and restore standard lid-sleep behavior.
3. **Mandatory Safety Timeout**:
   - Never allow indefinite, unbounded sleep-prevention sessions.
   - Default to a non-negotiable safe timer (e.g. 5 hours) to protect the machine if packed into a backpack.

---

## 4. State Machine & Crash Recovery Reconciliation

Persistent system settings (such as `pmset -a disablesleep 1`) survive process crashes and power loss:

1. **Persistent Session Ownership Record**:
   - Write session PID, start time, duration, and original system settings to disk (`~/.nosleepapp_state.json`).
2. **Startup Crash Detection**:
   - On launch, check if the system power setting is active (`pmset -g` matches `SleepDisabled 1`).
   - If active, verify whether the owning PID is still alive via `kill(pid, 0)`.
   - If the recorded PID is dead, trigger automatic reconciliation.
3. **Respect External User Configuration**:
   - If `SleepDisabled 1` is detected but no state file exists, do NOT revert it. The user may have manually configured it for their own purposes. Only reconcile when ownership is proven.
4. **Synchronous Termination Cleanup**:
   - Asynchronous background tasks are forcibly killed when an app terminates (`exit(0)`, `terminate`).
   - Cleanup in `applicationWillTerminate`, `applicationShouldTerminate`, and relocation must execute **synchronously** to guarantee power settings and brightness are restored before process exit.

---

## 5. Professional macOS Distribution & Asset Design

1. **Light Silver/Platinum DMG Aesthetic**:
   - Use authentic Apple light canvas tones (`#F8F9FB` to `#EBF0F7`) rather than harsh black or dark themes.
   - Use soft frosted guide cards with ambient drop shadows to seat icons.
   - Provide clear high-contrast typography in Apple system fonts.
2. **Custom Icon Stamping**:
   - Use native Cocoa `NSWorkspace.setIcon:forFile:options:` to stamp `.icns` onto `.dmg` and `.pkg` files (writing `com.apple.ResourceFork`).
   - For mounted volumes, copy `.VolumeIcon.icns` and set Finder attributes (`SetFile -a C`).
3. **Portable Relative Checksums**:
   - Never embed host-specific absolute paths (`/Users/username/...`) in verification manifests.
   - Generate checksums using relative paths from the project root so `shasum -c checksums.sha256` succeeds universally.
4. **Deliverable & Gitignore Consistency**:
   - If a repository documentation and release manifest promise ready-to-run `.dmg` and `.pkg` installers, ensure `.gitignore` does not exclude them while tracking their checksums.
