#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

echo "========================================================="
echo "             NoSleepApp macOS Installer                  "
echo "========================================================="
echo ""

# 1. Build application bundle
echo "🔨 1/3 Compiling and building NoSleepApp.app..."
"$SCRIPT_DIR/build_app.sh"

# 2. Copy to /Applications
echo "🚀 2/3 Installing to /Applications/NoSleepApp.app..."
killall NoSleepApp 2>/dev/null || true
rm -rf "/Applications/NoSleepApp.app"
cp -R "$ROOT_DIR/NoSleepApp.app" "/Applications/NoSleepApp.app"

# 3. Configure permanent passwordless sudo for pmset
echo "🔒 3/3 Setting up permanent 1-click passwordless permission..."
echo "     (Enter your Mac password ONCE below. You will never be asked again!)"

CURRENT_USER=$(id -un)
SUDOERS_FILE="/etc/sudoers.d/nosleepapp"

if [[ ! "$CURRENT_USER" =~ ^[a-z_][a-z0-9_.-]{0,31}$ ]]; then
    echo "❌ Invalid username format: $CURRENT_USER. Skipping sudoers setup."
else
    echo "$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" | sudo tee "$SUDOERS_FILE.tmp" >/dev/null
    sudo chown root:wheel "$SUDOERS_FILE.tmp"
    sudo chmod 0440 "$SUDOERS_FILE.tmp"

    if sudo /usr/sbin/visudo -c -f "$SUDOERS_FILE.tmp" >/dev/null 2>&1; then
        sudo mv "$SUDOERS_FILE.tmp" "$SUDOERS_FILE"
        echo "✓ Permanent passwordless permission successfully verified."
    else
        echo "⚠️ Sudoers check failed, removing temporary file."
        sudo rm -f "$SUDOERS_FILE.tmp"
    fi
fi

# Launch newly installed app
echo ""
echo "✨ Starting NoSleepApp..."
open "/Applications/NoSleepApp.app"

echo ""
echo "========================================================="
echo "   ✅ INSTALLATION COMPLETE!                             "
echo "========================================================="
echo "• NoSleepApp is now installed in /Applications"
echo "• Look at your top Mac menu bar for the 💤 icon"
echo "• Click the icon to start with 1-click (Zero passwords required!)"
echo "• Auto-off protection is set to 5 hours by default"
echo "========================================================="
