# NoSleepApp — UI/UX Design Specification & Design System

This specification defines the visual language, typography, color tokens, layout geometry, micro-interactions, and copy deck for **NoSleepApp**. It provides an exhaustive reference to re-create the user interface with exact fidelity.

---

## 1. Design Philosophy

1. **Apple Human Interface Guidelines (HIG) Native**: Feels like a built-in macOS system control (similar to Control Center, Battery, and Display menu extras).
2. **Minimalist Footprint**: Zero clutter on the menu bar (a single compact 18x18pt badge; no wide text labels).
3. **George Orwell’s Plain English Standard**:
   - *Never use a long word where a short one will do.*
   - *If it is possible to cut a word out, always cut it out.*
   - *Never use the passive where you can use the active.*
   - *Never use jargon if you can think of an everyday English equivalent.*
4. **Continuous Apple Curvature**: All rounded rectangles employ `style: .continuous` to prevent harsh corner transitions.

---

## 2. Color Palette & Design Tokens

### 2.1 Core Semantic Colors

| Token Name | Hex Code | RGB (0-1 / 0-255) | Usage |
| :--- | :--- | :--- | :--- |
| **`emerald-active`** | `#10B981` | `(0.06, 0.72, 0.51)` / `(16, 185, 129)` | Active menu bar badge, active countdown, success states |
| **`emerald-glow`** | `#34D399` | `(0.20, 0.83, 0.60)` / `(52, 211, 153)` | Active pill badge background, hover glows |
| **`cyan-accent`** | `#06B6D4` | `(0.02, 0.71, 0.83)` / `(6, 182, 212)` | Display / screen indicators, notice borders |
| **`amber-notice`** | `#FBBF24` | `(0.98, 0.75, 0.14)` / `(251, 191, 36)` | Demo countdown, reading phase badge, battery icon |
| **`red-alert`** | `#EF4444` | `(0.94, 0.27, 0.27)` / `(239, 68, 68)` | Disable CTA button, battery <20% cutoff warning |
| **`bg-hud`** | `#1F1F26` | `(0.12, 0.12, 0.15)` / `(31, 31, 38)` | Demo floating modal background |
| **`bg-card`** | `#121216` | `(0.07, 0.07, 0.09)` / `(18, 18, 22)` | Inner callout card background |
| **`border-subtle`**| `rgba(255, 255, 255, 0.2)` | Alpha 0.20 | Modal borders, divider outlines |

---

## 3. Typography Hierarchy

All typography uses the native Apple system font family (`.system(...)`).

| Element | Font Size | Weight | Design / Style | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Popover Header** | `13pt` | `.bold` | Default | App title next to shield icon |
| **Main Countdown** | `32pt` | `.medium` | `.monospaced` | Primary popover digital clock |
| **Demo Countdown** | `38pt` | `.bold` | `.monospaced` | Large central HUD clock |
| **HUD Header** | `16pt` | `.bold` | Default | "Screen Test" modal header |
| **Section Header** | `13pt` | `.bold` | Default | Inner card title ("How Screen Dimming Works") |
| **Primary Body** | `12pt` | `.regular` | Default | Modal explanations, list items |
| **Card Labels** | `11pt` | `.medium` | Default | "Screen when closed", "Power" |
| **Card Values** | `10.5pt` | `.semibold` | Default | "Turns off (0%)", "67% • Plugged in" |
| **CTA Button** | `12pt` | `.bold` | Default | Master toggle action ("ENABLE NO SLEEP") |
| **Status Pills** | `10pt` | `.bold` | Default | "READ (10s)", "TESTING (5s)", "DONE" |
| **Subtitles / Footers** | `9pt` | `.regular` | Default | Footer action links ("Test Screen", "Quit") |

---

## 4. Component Layout & Geometry

### 4.1 Menu Bar Item
- **Dimensions**: Square length (`18x18pt` canvas).
- **Idle Appearance**: Template system symbol `moon.zzz.fill` (rendered dynamically by macOS WindowServer to match wallpaper and dark/light menu bars).
- **Active Appearance**: Vector rendered emerald green circle with white centered lightning bolt (`bolt.fill`).

### 4.2 Popover Panel (`PopoverContentView`)
- **Dimensions**: Fixed width `280pt`, Content height $\approx 320\text{pt}$.
- **Padding**: `14pt` outer content padding.
- **Header**:
  - Left: Shield icon (`bolt.shield.fill`, `15pt`), App Title, Info button (`info.circle`, `13pt`).
  - Right: State capsule (`ACTIVE` in emerald / `IDLE` in gray).
- **Digital Clock**: `32pt` monospaced centered text + subtitle (`10pt`).
- **Preset Buttons**: 5 horizontal buttons (`1h`, `2h`, `3h`, `5h`, `8h`).
  - Height: `24pt`, corner radius `5pt`.
  - Selected state: Light tinted background + tint foreground color.
- **CTA Button**:
  - Full width, vertical padding `9pt`, corner radius `7pt`.
  - Idle: System accent color (`ENABLE NO SLEEP (5H)`).
  - Active: Red background (`DISABLE NO SLEEP`).
- **Safeguards Card**:
  - 2-row horizontal stack inside `RoundedRectangle(cornerRadius: 8)` with `8%` secondary opacity.
  - Row 1: `display.slash` (Cyan) | "Screen when closed" | "Turns off (0%)".
  - Row 2: `powerplug.fill` / `battery.50` | "Power" | "\(battery)% • Plugged in / Battery".

### 4.3 Floating HUD Modal (`DemoOverlayView`)
- **Dimensions**: Width `500pt`, Height `340pt`.
- **Window Masking**:
  - `NSWindow(styleMask: [.borderless])`.
  - Layer corner radius: `20pt`, `masksToBounds = true`.
  - SwiftUI root clip: `RoundedRectangle(cornerRadius: 20, style: .continuous)`.
  - Border stroke: `1.2pt` white with `0.2` opacity.
  - Native WindowServer drop shadow: Activated via `win.invalidateShadow()`.
- **Window Level**: Elevated to `NSWindow.Level(rawValue: 200)` to float above all popovers.
- **Display Centering**: Calculated from `NSScreen.main.visibleFrame` midpoint.

---

## 5. Complete Copy Deck (Orwellian Plain English)

### 5.1 Main Popover
- **Header**: `NoSleepApp`
- **Info Icon Tooltip**: `Why keep your Mac awake? Click to learn more.`
- **Timer Subtitle (Active)**: `Will stop automatically`
- **Timer Subtitle (Idle)**: `Stops after 5 hours`
- **CTA Button (Idle)**: `ENABLE NO SLEEP (5H)`
- **CTA Button (Active)**: `DISABLE NO SLEEP`
- **Safeguards Card Row 1**: `Screen when closed` → `Turns off (0%)`
- **Safeguards Card Row 2**: `Power` → `\(battery)% • Plugged in` *(or `\(battery)% • Battery (stops under 20%)`)*
- **Safeguards Tooltip**: `Turns the screen off when you shut the lid to keep the keyboard cool. Stops automatically if battery drops below 20%.`
- **Footer Left**: `Test Screen (10s)` | Tooltip: `Shows how screen dimming works, then tests 5% brightness for 5 seconds.`
- **Footer Right**: `Quit App` | Tooltip: `Completely exits NoSleepApp. Restores normal sleep and screen brightness.`

### 5.2 The 10-Second Demo Modal
- **Title**: `Screen Test`
- **Status Badges**:
  - Phase 1: `READ (10s)` (Amber)
  - Phase 2: `TESTING (5s)` (Emerald)
  - Phase 3: `DONE` (Emerald)
- **Section Title**: `How Screen Dimming Works`
- **Item 1**:
  - Badge: Cyan Circle (`6x6pt`)
  - Header: `In this 5-second test:`
  - Body: `The screen dims to 5% so you can still read this text.`
- **Item 2**:
  - Badge: Yellow Circle (`6x6pt`)
  - Header: `When you close the lid:`
  - Body: `The screen turns off completely (0%) so it does not heat your laptop.`
- **Status Counters**:
  - Phase 1: `5% dim test starts in 10 seconds...`
  - Phase 2: `Testing 5% screen. Resetting in 5s...`
  - Phase 3: `✓ Test done. Normal brightness restored.`
- **Bottom Button**: `Stop Test` (during active test) / `Close` (at completion).

### 5.3 `ⓘ` Info Guide (Why Keep Your Mac Awake?)
- **Item 1**: `Run AI Agents` — *Close the lid while Hermes, Claude, or local tasks finish work.*
- **Item 2**: `Remote Access` — *Reach your closed Mac over SSH or remote desktop from anywhere.*
- **Item 3**: `Large Downloads` — *Download big files overnight without leaving the screen on.*
- **Item 4**: `Safe Auto-Off` — *Stops after 5 hours or if your battery falls below 20%.*
- **Button**: `← Back to Controls`
