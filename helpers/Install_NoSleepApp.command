#!/usr/bin/env bash
# Install_NoSleepApp.command
# Double-click this script in Finder to install NoSleepApp like a standard application.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

echo "=========================================="
echo "    Installing NoSleepApp to your Mac...  "
echo "=========================================="

# 1. Stop any currently running instance
killall NoSleepApp 2>/dev/null || true

# 2. Ensure NoSleepApp.app exists or build it
if [ ! -d "NoSleepApp.app" ]; then
    echo "🔨 Building fresh app bundle..."
    "$ROOT_DIR/scripts/build_app.sh"
fi

# 3. Install to /Applications
echo "📦 Installing into /Applications/NoSleepApp.app..."
rm -rf "/Applications/NoSleepApp.app"
cp -R "NoSleepApp.app" "/Applications/"

# 4. Configure permanent passwordless permission
echo "🔐 Setting up 1-time passwordless permission..."
USER_NAME=$(id -un)

if [[ ! "$USER_NAME" =~ ^[a-z_][a-z0-9_.-]{0,31}$ ]]; then
    echo "⚠️ Invalid username format ($USER_NAME). Skipping automated sudoers configuration."
else
    RULE="$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    sudo mkdir -p /etc/sudoers.d
    echo "$RULE" | sudo tee /etc/sudoers.d/nosleepapp.tmp > /dev/null
    sudo chown root:wheel /etc/sudoers.d/nosleepapp.tmp
    sudo chmod 0440 /etc/sudoers.d/nosleepapp.tmp
    if sudo /usr/sbin/visudo -c -f /etc/sudoers.d/nosleepapp.tmp >/dev/null 2>&1; then
        sudo mv /etc/sudoers.d/nosleepapp.tmp /etc/sudoers.d/nosleepapp
    else
        sudo rm -f /etc/sudoers.d/nosleepapp.tmp
    fi
fi

# 5. Launch from /Applications
echo "🚀 Launching NoSleepApp..."
open "/Applications/NoSleepApp.app"

# 6. Show friendly system confirmation dialog
osascript -e 'display alert "NoSleepApp Installed Successfully" message "NoSleepApp is now installed in /Applications and active in your top-right menu bar.\n\nClick the moon icon to enable No Sleep mode!" as informational'

echo "✅ Installation complete! You can close this window."
