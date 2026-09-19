# NoSleepApp for macOS

<div align="center">

[![macOS](https://img.shields.io/badge/macOS-12.0%2B%20(Monterey%20--%20Sequoia)-blue?logo=apple&style=for-the-badge)](https://github.com/Prashant23saxena/NoSleepApp)
[![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(M1--M4)%20%7C%20Intel-success?style=for-the-badge)](https://github.com/Prashant23saxena/NoSleepApp)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift&style=for-the-badge)](https://github.com/Prashant23saxena/NoSleepApp)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero%20(Native%20APIs)-purple?style=for-the-badge)](https://github.com/Prashant23saxena/NoSleepApp)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

**Keep your closed-lid MacBook awake — safely, silently, and with zero heat build-up.**  
*Purpose-built for long-running AI coding agents (Claude, Hermes, Antigravity), torrent downloads, compilation jobs, and overnight tasks.*

[Quick Install](#-quick-install) • [Why NoSleepApp?](#-why-nosleepapp) • [Comparison](#-feature-comparison-matrix) • [Hardware Safeguards](#-hardware-thermal-safeguards) • [FAQ](#-frequently-asked-questions-faq) • [Docs](docs/ARCHITECTURE.md)

</div>

---

## ⚡ What is NoSleepApp?

**NoSleepApp** is a lightweight, zero-dependency macOS menu-bar utility designed to prevent MacBooks from going to sleep when the lid is closed, even on battery power without external monitors or chargers.

Unlike legacy kernel extensions that compromise system security or simple `caffeinate` commands that fail when the lid closes on battery, NoSleepApp combines **native power assertion management**, **automatic 0% screen backlight dimming**, and **real-time kernel battery telemetry** to ensure your laptop completes background workloads safely without overheating.

```
                  ┌──────────────────────────────────────────────┐
                  │              macOS Menu Bar                  │
                  │  [ ⚡ NoSleepApp • 04:59:12 remaining ]      │
                  └──────────────────────┬───────────────────────┘
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        ▼                                ▼                                ▼
┌──────────────────────┐      ┌──────────────────────┐      ┌──────────────────────┐
│  Lid Sleep Blocked   │      │ 0% Backlight Dimming │      │  Hardware Safeguards │
│ Mac stays 100% awake │      │ Screen off via C API │      │ Auto-off after 5 hrs │
│ for AI/torrents/jobs │      │ Zero keyboard heat   │      │ 20% battery cutoff   │
└──────────────────────┘      └──────────────────────┘      └──────────────────────┘
```

---

## 🚀 Quick Install

Choose your preferred installation method:

<details open>
<summary><b>Option 1: Drag-and-Drop DMG Installer (Recommended)</b></summary>
<br>

1. Download or open [**`NoSleepApp.dmg`**](NoSleepApp.dmg).
2. Drag **NoSleepApp** into the **Applications** folder shortcut.
3. Launch `NoSleepApp` from Spotlight (`Cmd + Space`) or Launchpad.

> **Tip**: If you double-click `NoSleepApp` directly from Downloads, the app will automatically ask: *"Move to Applications folder?"* and install itself with a single click.
</details>

<details>
<summary><b>Option 2: Standard macOS Package Wizard (<code>.pkg</code>)</b></summary>
<br>

1. Double-click [**`NoSleepApp.pkg`**](NoSleepApp.pkg).
2. Follow the standard guided macOS installation wizard.
3. Automatically sets up passwordless execution rights and places the application in `/Applications`.
</details>

<details>
<summary><b>Option 3: Terminal / One-Click Desktop Helpers</b></summary>
<br>

Open the **`helpers/`** folder in Finder and double-click:
- **`Install_NoSleepApp.command`**: Installs the app to `/Applications` and configures permissions.
- **`Setup_Passwordless_Mode.command`**: Configures 1-click passwordless mode without manual terminal commands.
- **`NoSleepApp.command`**: Launches the app directly.

Or compile and run directly from source:
```bash
git clone https://github.com/Prashant23saxena/NoSleepApp.git
cd NoSleepApp
./scripts/build_app.sh
open NoSleepApp.app
```
</details>

---

## 🎯 Why NoSleepApp? (The Problem with Clamshell Sleep)

On modern macOS (especially Apple Silicon M1, M2, M3, and M4), Apple enforces strict clamshell sleep:
- If a MacBook is **unplugged from AC power** or has **no external monitor connected**, closing the lid forces immediate system sleep.
- Built-in command line tools like `caffeinate -d` or `caffeinate -s` **only prevent idle sleep**. They are overridden by hardware lid-close events.
- If an app forces the laptop awake with the screen illuminated inside a closed lid, heat gets trapped between the retina display and the keyboard, risking hardware degradation.

**NoSleepApp solves all three problems:**
1. **True Clamshell Sleep Prevention**: Uses native system power assertions (`pmset -a disablesleep 1`) to ensure background processes never sleep.
2. **0% Backlight Dimming**: Dynamically connects to Apple's private `DisplayServices.framework` to set backlight brightness to `0.00` while active, preventing heat accumulation.
3. **Triple Safety Protection**: Enforces an automatic 5-hour timeout, instant 20% battery cutoff, and dead-process crash recovery.

---

## 📊 Feature Comparison Matrix

| Feature | `NoSleepApp` | `caffeinate` (macOS CLI) | `Amphetamine` | Legacy `NoSleep` (kext) |
| :--- | :---: | :---: | :---: | :---: |
| **Keeps Closed Lid Awake on Battery** | ✅ **Yes** | ❌ No (requires AC + display) | ⚠️ Partial (fails on modern macOS) | ✅ Yes |
| **0% Display Backlight Heat Elimination** | ✅ **Yes (0% via C API)** | ❌ No | ❌ No | ❌ No |
| **Zero Third-Party Dependencies** | ✅ **Yes (Native Swift/C)** | ✅ Yes | ❌ No | ❌ No |
| **Kernel Extension (KEXT) Required** | ❌ **No (100% User Space)** | ❌ No | ❌ No | ⚠️ Yes (requires SIP disable) |
| **Apple Silicon Native (M1/M2/M3/M4)** | ✅ **Native arm64** | ✅ Yes | ✅ Yes | ❌ Broken / Incompatible |
| **Automatic 5-Hour Safety Cutoff** | ✅ **Built-in** | ❌ Manual flag | ⚠️ Optional | ❌ No |
| **Instant 20% Battery Protection** | ✅ **Real-time IOKit** | ❌ No | ⚠️ Delayed poll | ❌ No |
| **Dead-Process Crash Reconciler** | ✅ **Automatic** | ❌ No | ❌ No | ❌ No |
| **1-Click Passwordless Sudo** | ✅ **Included** | ❌ Requires manual sudo | N/A | N/A |

---

## 🛡️ Hardware & Thermal Safeguards

<details open>
<summary><b>1. 0% Screen Backlight Dimming (Heat Elimination)</b></summary>
<br>

Keeping a MacBook awake with the screen powered creates concentrated heat between the keyboard and the delicate display coating. NoSleepApp loads macOS private `DisplayServices.framework`:
```c
DisplayServicesSetBrightness(CGMainDisplayID(), 0.00);
```
- Backlight is turned completely off (0%) when active.
- Original brightness is saved to disk and restored instantly upon exit.
- If display services are unavailable on a future macOS version, NoSleepApp warns the user and advises ventilation.
</details>

<details>
<summary><b>2. 5-Hour Automatic Safety Cutoff</b></summary>
<br>

Never worry about your laptop staying awake inside a backpack:
- Every session defaults to a non-negotiable **5-hour countdown timer**.
- Quick presets available: `1 Hour`, `2 Hours`, `5 Hours`, `8 Hours`.
- Live visual countdown ring displayed directly in your macOS menu bar.
</details>

<details>
<summary><b>3. Instant 20% Battery Safeguard (IOKit Telemetry)</b></summary>
<br>

Rather than polling slow shell commands, NoSleepApp registers an event source on `CFRunLoopGetMain()` via native Apple `IOKit.ps` (`IOPSNotificationCreateRunLoopSource`):
- Detects the instant power is unplugged or battery drops to $\le 20\%$.
- Immediately restores normal sleep behavior to protect battery health and prevent unexpected shutdowns.
- For desktop Macs (Mac mini, Mac Studio, Mac Pro), automatically detects continuous power and adjusts UI indicators.
</details>

<details>
<summary><b>4. Crash Recovery Reconciler (No Orphaned Settings)</b></summary>
<br>

System power flags (`pmset disablesleep 1`) survive unexpected application termination (`kill -9`, power loss):
- NoSleepApp records session ownership in `~/.nosleepapp_state.json`.
- On launch, if `SleepDisabled 1` is detected, it probes the owning PID via `kill(pid, 0)`.
- If the PID is dead, it restores default sleep settings automatically without popping unprompted password dialogues.
</details>

---

## ❓ Frequently Asked Questions (FAQ)

<details open>
<summary><b>Does NoSleepApp work on Apple Silicon (M1, M2, M3, M4)?</b></summary>
<br>
Yes. NoSleepApp is compiled natively for Apple Silicon (arm64) and Intel (x86_64). It requires macOS 12.0 (Monterey) or later, including macOS 14 (Sonoma) and macOS 15 (Sequoia).
</details>

<details>
<summary><b>Why does NoSleepApp dim the screen to 0%?</b></summary>
<br>
When a MacBook lid is closed, the display sits flush against the keyboard. If the backlight remains on (even at low levels), heat gets trapped, causing the laptop to run hot and wasting battery. Setting backlight brightness to 0% eliminates display heat entirely while allowing the CPU and GPU to continue running background workloads.
</details>

<details>
<summary><b>How is NoSleepApp different from <code>caffeinate</code>?</b></summary>
<br>
macOS includes a built-in command <code>caffeinate</code>. However, <code>caffeinate</code> only prevents idle sleep while the lid remains open (or when connected to both an external display and AC power). When you close the lid on battery power, macOS overrides <code>caffeinate</code> and puts the machine to sleep. NoSleepApp sets the system-level clamshell sleep parameter so your workload continues uninterrupted.
</details>

<details>
<summary><b>Does NoSleepApp require disabling SIP (System Integrity Protection)?</b></summary>
<br>
No. Unlike legacy tools from a decade ago that required installing unstable kernel extensions (.kext) and disabling SIP, NoSleepApp operates 100% in user space using standard Apple power management APIs. System Integrity Protection remains fully enabled.
</details>

<details>
<summary><b>Can I test the screen dimming feature before closing my lid?</b></summary>
<br>
Yes! Click the <b>Test 10s Screen Dimming</b> button in the app popover. It displays an educational high-contrast card for 10 seconds, dims the display to 5% for 5 seconds to demonstrate the effect, and then automatically restores your exact previous brightness.
</details>

---

## 📁 Repository Directory Hierarchy

```text
NoSleepApp/
│
├── NoSleepApp.dmg             # 💿 Primary drag-and-drop installer disk image (Light Silver)
├── NoSleepApp.pkg             # 📦 Standard macOS guided installer package
├── NoSleepApp.app/            # 🚀 Ready-to-run macOS application bundle
├── README.md                  # 📖 Master guide & directory architecture (this file)
├── llms.txt                   # 🤖 Machine-readable project context for AI search engines
│
├── docs/                      # 📚 Centralized Technical Documentation
│   ├── ARCHITECTURE.md        # Deep-dive system architecture, IOKit & power daemon
│   ├── DESIGN_SPEC.md         # UI/UX design tokens, colors, typography & geometry
│   └── LLM_REPRODUCTION_GUIDE.md # AI/LLM blueprint to reproduce the entire project
│
├── learning_feedback/         # 🎓 User Feedback Archive & Codified Systems Wisdom
│   ├── README.md              # Navigation guide and feedback domain index
│   ├── USER_FEEDBACK_ANALYSIS.md # Domain-by-domain analysis (Security, Thermal, UX)
│   ├── CHRONOLOGICAL_FEEDBACK_LOG.md # Complete audit log across all user prompts
│   └── RULES_AND_BEST_PRACTICES.md # Codified rules for macOS system development
│
├── src/                       # 💻 Core Source Code (Zero External Dependencies)
│   ├── NoSleepApp.swift       # Native Swift menu bar controller & SwiftUI UI
│   ├── brightness.c           # C DisplayServices hardware backlight controller
│   └── nosleep.sh             # Pure POSIX shell daemon & power controller
│
├── scripts/                   # ⚙️ Build and Distribution Toolchain
│   ├── build_app.sh           # Compiles Swift & C into NoSleepApp.app
│   ├── build_styled_dmg.sh    # Builds the styled DMG with custom Finder layout
│   ├── package_dist.sh        # Orchestrates full distribution (DMG + PKG)
│   ├── install.sh             # Terminal installer with passwordless setup
│   ├── uninstall.sh           # Clean uninstaller & system power settings reset
│   └── generate_dmg_background.py # Retina visual asset generator for DMG window
│
├── assets/                    # 🎨 App Icons & Visual Assets
│   ├── AppIcon.icns           # High-resolution macOS application icon
│   └── dmg_background.png     # Custom Retina background for the DMG installer
│
└── helpers/                   # 🖱️ Double-Clickable Finder Desktop Helpers
    ├── Install_NoSleepApp.command      # Double-click to install directly to /Applications
    ├── Setup_Passwordless_Mode.command # 1-time setup for passwordless mode
    └── NoSleepApp.command              # 1-click launcher for the app
```

---

## 🛠️ Build & Developer Commands

All build scripts are located in `scripts/` and run from the repository root:

```bash
# 1. Compile Swift application bundle (NoSleepApp.app)
./scripts/build_app.sh

# 2. Build styled DMG installer with custom Finder layout
./scripts/build_styled_dmg.sh

# 3. Build complete distribution package (NoSleepApp.app + .dmg + .pkg + checksums)
./scripts/package_dist.sh

# 4. Verify cryptographic package integrity
shasum -c checksums.sha256

# 5. Clean uninstall and restore system power defaults
./scripts/uninstall.sh
```

---

## 📚 Technical Documentation Index

- [**docs/ARCHITECTURE.md**](docs/ARCHITECTURE.md): Native Apple power management architecture, `pmset disablesleep`, `IOKit` power telemetry, DisplayServices C bindings, and security models.
- [**docs/DESIGN_SPEC.md**](docs/DESIGN_SPEC.md): Complete UI/UX design specifications, color palettes (Zinc/Emerald/Amber), typography, animations, and George Orwell plain-English copy guidelines.
- [**docs/LLM_REPRODUCTION_GUIDE.md**](docs/LLM_REPRODUCTION_GUIDE.md): Instructions and prompts for an LLM or autonomous AI agent to reproduce this entire project from scratch.
- [**learning_feedback/README.md**](learning_feedback/README.md): Comprehensive archive of all user feedback, architectural evolutions, and codified engineering rules.

---

## 📄 License & Integrity

This project is licensed under the [MIT License](LICENSE).  
Verified on macOS Monterey through macOS Sequoia across Apple Silicon (M1/M2/M3/M4) and Intel architectures.
