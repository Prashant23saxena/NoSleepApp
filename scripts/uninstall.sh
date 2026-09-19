#!/usr/bin/env bash
set -e

# ==============================================================================
# NoSleepApp - Uninstaller for macOS
# Cleanly uninstalls NoSleepApp and restores all original system settings.
# ==============================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo "             NoSleepApp Uninstaller                      "
echo "========================================================="
echo ""

echo "• Stopping NoSleepApp..."
killall NoSleepApp 2>/dev/null || true

echo "• Restoring normal Mac sleep settings..."
sudo pmset -a disablesleep 0 2>/dev/null || true

echo "• Removing /Applications/NoSleepApp.app..."
rm -rf "/Applications/NoSleepApp.app"
rm -rf "$DIR/NoSleepApp.app"

echo "• Removing passwordless sudoers configuration..."
sudo rm -f "/etc/sudoers.d/nosleepapp" 2>/dev/null || true

echo ""
echo "========================================================="
echo "   ✓ NoSleepApp completely uninstalled.                  "
echo "   ✓ System sleep & power settings restored to normal.   "
echo "========================================================="
