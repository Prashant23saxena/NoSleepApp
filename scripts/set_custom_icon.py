#!/usr/bin/env python3
"""
set_custom_icon.py
Applies a custom .icns icon to files, DMG disk images, PKG installers,
or mounted macOS volumes using native Cocoa NSWorkspace APIs.
"""

import sys
import os

def set_icon(icon_path, target_path):
    if not os.path.exists(icon_path):
        print(f"❌ Icon not found: {icon_path}")
        return False
    if not os.path.exists(target_path):
        print(f"❌ Target not found: {target_path}")
        return False

    try:
        from Cocoa import NSWorkspace, NSImage
        ws = NSWorkspace.sharedWorkspace()
        abs_icon = os.path.abspath(icon_path)
        abs_target = os.path.abspath(target_path)

        img = NSImage.alloc().initWithContentsOfFile_(abs_icon)
        if not img:
            print(f"❌ Failed to load image from: {abs_icon}")
            return False

        success = ws.setIcon_forFile_options_(img, abs_target, 0)
        if success:
            print(f"🎨 Successfully applied custom icon to: {target_path}")
        else:
            print(f"⚠️ Failed to apply icon to: {target_path}")
        return success
    except Exception as e:
        print(f"❌ Error applying icon: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 set_custom_icon.py <path_to_icon.icns> <target_file_or_dir> [...]")
        sys.exit(1)

    icon = sys.argv[1]
    for target in sys.argv[2:]:
        set_icon(icon, target)
