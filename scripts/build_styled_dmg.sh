#!/usr/bin/env bash
# build_styled_dmg.sh
# Builds an Apple-grade, professionally styled macOS Drag-to-Install DMG
# with custom volume icon, light silver background, and centered 120px icons.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

VOL_NAME="NoSleepApp Installer"
FINAL_DMG="$ROOT_DIR/NoSleepApp.dmg"
TEMP_DMG="$ROOT_DIR/temp_installer.dmg"
ICON_PATH="$ROOT_DIR/assets/AppIcon.icns"

echo "🎨 1. Generating Apple-grade Light Silver DMG background..."
python3 "$SCRIPT_DIR/generate_dmg_background.py" "$ROOT_DIR/assets/dmg_background.png"

echo "🧹 2. Cleaning previous mounts and artifacts..."
hdiutil detach "/Volumes/$VOL_NAME" -force 2>/dev/null || true
rm -f "$TEMP_DMG" "$FINAL_DMG"

echo "💿 3. Creating read-write temporary disk image..."
hdiutil create -size 120m -fs HFS+ -volname "$VOL_NAME" -ov "$TEMP_DMG"

echo "📂 4. Mounting disk image..."
MOUNT_INFO=$(hdiutil attach "$TEMP_DMG" -readwrite -nobrowse)
MOUNT_DIR=$(echo "$MOUNT_INFO" | grep -o '/Volumes/.*' | head -n 1)
if [ -z "$MOUNT_DIR" ]; then
    MOUNT_DIR="/Volumes/$VOL_NAME"
fi

if [ ! -d "$MOUNT_DIR" ]; then
    echo "❌ Failed to find mount directory: $MOUNT_DIR"
    exit 1
fi
echo "   Mounted at: $MOUNT_DIR"

echo "📥 5. Copying application bundle and shortcuts..."
cp -R "$ROOT_DIR/NoSleepApp.app" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

echo "🎨 6. Setting custom Volume Icon on mounted disk..."
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$MOUNT_DIR/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
    else
        echo "   (Note: Xcode SetFile utility not installed; using native Cocoa icon engine)"
    fi
    python3 "$SCRIPT_DIR/set_custom_icon.py" "$ICON_PATH" "$MOUNT_DIR" 2>/dev/null || true
fi

mkdir -p "$MOUNT_DIR/.background"
cp "$ROOT_DIR/assets/dmg_background.png" "$MOUNT_DIR/.background/background.png"
chmod -R 755 "$MOUNT_DIR/.background"
chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true

echo "🖼️ 7. Applying Finder layout via AppleScript..."
osascript << EOF || echo "⚠️ Finder layout could not be applied via AppleScript (running headless/CI); proceeding..."
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 120
        set background picture of viewOptions to file ".background:background.png"
        
        set the bounds of container window to {200, 120, 860, 540}
        delay 1
        
        set position of item "NoSleepApp.app" of container window to {160, 195}
        set position of item "Applications" of container window to {500, 195}
        
        delay 1
        close
        delay 1
        open
        delay 1
        set position of item "NoSleepApp.app" of container window to {160, 195}
        set position of item "Applications" of container window to {500, 195}
        update without registering applications
        delay 2
    end tell
end tell
EOF

echo "🔒 8. Finalizing and detaching..."
sync
sleep 2

for i in {1..5}; do
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null && break
    sleep 1
done || hdiutil detach "$MOUNT_DIR" -force -quiet 2>/dev/null || true

echo "🗜️ 9. Converting to compressed read-only DMG (UDZO)..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
rm -f "$TEMP_DMG"

echo "🎨 10. Applying custom icon to the final .dmg file..."
if [ -f "$ICON_PATH" ]; then
    python3 "$SCRIPT_DIR/set_custom_icon.py" "$ICON_PATH" "$FINAL_DMG"
fi

echo "✅ Apple-Grade Styled DMG created: $FINAL_DMG"
ls -lh "$FINAL_DMG"
