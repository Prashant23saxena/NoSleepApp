# NoSleepApp for macOS

> **Keep your MacBook running with the lid closed — safely, silently, and with zero heat buildup.**  
> Purpose-built for long-running AI coding agents (Hermes, Claude, Antigravity), torrent downloads, and overnight workloads.

---

## 📁 Repository Directory Hierarchy

This project follows a clean, professional architecture so any human developer or AI agent can immediately understand the purpose of every folder and file.

```text
NoSleepApp/
│
├── NoSleepApp.dmg             # 💿 Primary drag-and-drop installer disk image
├── NoSleepApp.pkg             # 📦 Standard macOS guided installer package
├── NoSleepApp.app/            # 🚀 Ready-to-run macOS application bundle
├── README.md                  # 📖 Master guide & directory architecture (this file)
│
├── docs/                      # 📚 ALL documentation in one place
│   ├── ARCHITECTURE.md        # Deep-dive system architecture, IOKit & power daemon
│   ├── DESIGN_SPEC.md         # UI/UX design tokens, colors, typography & geometry
│   └── LLM_REPRODUCTION_GUIDE.md # AI/LLM blueprint to reproduce the entire project
│
├── learning_feedback/         # 🎓 User feedback analysis & engineering lessons
│   ├── README.md              # Navigation guide and feedback domain index
│   ├── USER_FEEDBACK_ANALYSIS.md # Domain-by-domain analysis (Security, Thermal, UX)
│   ├── CHRONOLOGICAL_FEEDBACK_LOG.md # Complete audit log across all user prompts
│   └── RULES_AND_BEST_PRACTICES.md # Codified rules for macOS system development
│
├── src/                       # 💻 Core source code
│   ├── NoSleepApp.swift       # Native Swift menu bar controller & SwiftUI UI
│   ├── brightness.c           # C DisplayServices hardware backlight controller
│   └── nosleep.sh             # Pure POSIX shell daemon & power controller
│
├── scripts/                   # ⚙️ Build and distribution toolchain
│   ├── build_app.sh           # Compiles Swift & C into NoSleepApp.app
│   ├── build_styled_dmg.sh    # Builds the styled DMG with custom Finder layout
│   ├── package_dist.sh        # Orchestrates full distribution (DMG + PKG)
│   ├── install.sh             # Terminal installer with passwordless setup
│   ├── uninstall.sh           # Clean uninstaller & system power settings reset
│   └── generate_dmg_background.py # Retina visual asset generator for DMG window
│
├── assets/                    # 🎨 App icons and visual assets
│   ├── AppIcon.icns           # High-resolution macOS application icon
│   └── dmg_background.png     # Custom Retina background for the DMG installer
│
└── helpers/                   # 🖱️ Double-clickable desktop helper scripts
    ├── Install_NoSleepApp.command      # Double-click to install directly to /Applications
    ├── Setup_Passwordless_Mode.command # 1-time setup for passwordless mode
    └── NoSleepApp.command              # 1-click launcher for the app
```

---

## 🗂️ Folder Purpose & Responsibilities

| Directory | Purpose | Notes for Developers & AI Agents |
| :--- | :--- | :--- |
| **`docs/`** | **Centralized Documentation** | Contains all technical deep-dives, UI design tokens, and LLM reproduction guides. If modifying architecture or UI styling, update docs here first. |
| **`learning_feedback/`** | **Feedback & Engineering Wisdom** | Complete repository of all user critiques, bug reports, chronological audit logs, and codified rules for macOS systems programming. |
| **`src/`** | **Application Source Code** | Pure Swift, C, and Shell source files. Zero external third-party dependencies. Compiles directly with native Apple clang/swiftc. |
| **`scripts/`** | **Build & Packaging Toolchain** | Automated shell and python scripts to compile binaries, style disk images in Finder, and build signed installer packages. |
| **`assets/`** | **Visual Assets & Icons** | Production `.icns` application icons and `@2x` Retina DMG background graphics. |
| **`helpers/`** | **Finder Desktop Helpers** | `.command` files that users can double-click directly in Finder without opening Terminal. |

---

## 🚀 How to Install

Choose whichever method you prefer:

### Option 1: Drag-to-Install DMG (Recommended)
1. Double-click **`NoSleepApp.dmg`**.
2. Drag **`NoSleepApp`** into the **`Applications`** folder shortcut.
3. Open **`NoSleepApp`** from your Applications folder or Spotlight (`Cmd + Space`).
4. *(Self-Moving Feature)*: If you simply double-click `NoSleepApp` inside the disk image or Downloads, it will automatically ask: *"Move to Applications folder?"* and install itself with one click.

### Option 2: Standard macOS Package Wizard (`.pkg`)
1. Double-click **`NoSleepApp.pkg`**.
2. Follow the standard macOS installer wizard.
3. Automatically sets up passwordless permission and starts the app.

### Option 3: Double-Click Helper
1. Open the **`helpers/`** folder.
2. Double-click **`Install_NoSleepApp.command`**.

---

## 🛡️ Built-in Laptop Hardware Safeguards

Running a laptop with the lid closed can cause hardware damage if not designed carefully. NoSleepApp solves this with three automatic safeguards:

1. **0% Screen Backlight Dimming**:
   - The screen backlight generates substantial heat beneath a closed lid.
   - When active, NoSleepApp dims the screen backlight to **0%** via Apple private DisplayServices APIs, keeping the laptop cool.
   - Automatically restores your exact original brightness when turned off.
2. **5-Hour Safety Auto-Off Timer**:
   - Default timer stops sessions automatically after 5 hours.
   - Prevents your MacBook from staying awake indefinitely if forgotten in a backpack.
3. **20% Low Battery Cutoff**:
   - Uses zero-latency native `IOKit.ps` power telemetry.
   - If unplugged from AC power and battery drops below 20%, the app turns itself off and allows normal sleep to preserve battery life.

---

## 🛠️ Build & Developer Commands

All build scripts are located in the `scripts/` directory and can be run from the repository root:

```bash
# 1. Compile Swift application bundle
./scripts/build_app.sh

# 2. Build styled DMG installer with custom Finder layout
./scripts/build_styled_dmg.sh

# 3. Build complete distribution (NoSleepApp.app + NoSleepApp.dmg + NoSleepApp.pkg)
./scripts/package_dist.sh

# 4. Uninstall app and restore system power defaults
./scripts/uninstall.sh
```

---

## 📚 Technical Documentation & Learning Index

For detailed engineering, design, and reproduction details, explore the **`docs/`** and **`learning_feedback/`** directories:

### Core Documentation
- [**docs/ARCHITECTURE.md**](docs/ARCHITECTURE.md): Native Apple power management architecture, `pmset disablesleep`, `IOKit` power telemetry, DisplayServices C bindings, and security models.
- [**docs/DESIGN_SPEC.md**](docs/DESIGN_SPEC.md): Complete UI/UX design specifications, color palettes (Zinc/Emerald/Amber), typography, animations, and George Orwell plain-English copy guidelines.
- [**docs/LLM_REPRODUCTION_GUIDE.md**](docs/LLM_REPRODUCTION_GUIDE.md): Complete instructions and prompts for an LLM or autonomous AI agent to reproduce this entire project from scratch on any macOS system.

### Learning & User Feedback Knowledge Base
- [**learning_feedback/README.md**](learning_feedback/README.md): Master index and summary of engineering lessons learned from user feedback.
- [**learning_feedback/USER_FEEDBACK_ANALYSIS.md**](learning_feedback/USER_FEEDBACK_ANALYSIS.md): Comprehensive analysis across 5 key technical domains (Security, Heat, UX, Concurrency, Hierarchy).
- [**learning_feedback/CHRONOLOGICAL_FEEDBACK_LOG.md**](learning_feedback/CHRONOLOGICAL_FEEDBACK_LOG.md): Full chronological audit trail mapping user feedback and remediations from Step 0 to Step 1144+.
- [**learning_feedback/RULES_AND_BEST_PRACTICES.md**](learning_feedback/RULES_AND_BEST_PRACTICES.md): Codified rules for macOS system programming, Orwellian UI copy, and safe privilege delegation.
