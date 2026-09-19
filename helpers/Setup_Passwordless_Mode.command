#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "========================================================="
echo "   NoSleepApp - 1-Time Passwordless Permission Setup     "
echo "========================================================="
echo "This configures your Mac so NoSleepApp can enable and"
echo "disable lid sleep with 1-click without password prompts."
echo ""
echo "Please enter your Mac admin password below ONCE:"

CURRENT_USER=$(id -un)
SUDOERS_FILE="/etc/sudoers.d/nosleepapp"

if [[ ! "$CURRENT_USER" =~ ^[a-z_][a-z0-9_.-]{0,31}$ ]]; then
    echo "❌ Invalid username format: $CURRENT_USER"
    exit 1
fi

echo "$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" | sudo tee "$SUDOERS_FILE.tmp" >/dev/null
sudo chown root:wheel "$SUDOERS_FILE.tmp"
sudo chmod 0440 "$SUDOERS_FILE.tmp"

if sudo /usr/sbin/visudo -c -f "$SUDOERS_FILE.tmp" >/dev/null 2>&1; then
    sudo mv "$SUDOERS_FILE.tmp" "$SUDOERS_FILE"
    echo ""
    echo "========================================================="
    echo "   ✅ SUCCESS! Passwordless Mode is permanently active!  "
    echo "========================================================="
    echo "• You will NEVER be asked for a password again when"
    echo "  enabling or disabling NoSleepApp or running the timer."
else
    echo "⚠️ Setup failed. Cleaning up."
    sudo rm -f "$SUDOERS_FILE.tmp"
fi

echo ""
read -p "Press [Enter] to close this window..."
