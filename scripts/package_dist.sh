#!/usr/bin/env bash
# package_dist.sh
# Orchestrates complete macOS distribution packaging:
# 1. Compiles NoSleepApp.app via scripts/build_app.sh
# 2. Generates styled NoSleepApp.dmg via scripts/build_styled_dmg.sh
# 3. Builds guided NoSleepApp.pkg wizard

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

echo "🔨 1. Compiling NoSleepApp.app..."
"$SCRIPT_DIR/build_app.sh"

echo "📦 2. Generating styled NoSleepApp.dmg (Drag to Applications disk image)..."
"$SCRIPT_DIR/build_styled_dmg.sh"

echo "📦 3. Generating NoSleepApp.pkg (Apple Installer Package)..."
PKG_ROOT="$ROOT_DIR/pkg_root"
PKG_SCRIPTS="$ROOT_DIR/pkg_scripts"
rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "$ROOT_DIR/NoSleepApp.pkg"
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_SCRIPTS"

cp -R "$ROOT_DIR/NoSleepApp.app" "$PKG_ROOT/Applications/"

cat << 'EOF' > "$PKG_SCRIPTS/postinstall"
#!/bin/bash
CONSOLE_USER=$(stat -f "%Su" /dev/console)
if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then
    mkdir -p /etc/sudoers.d
    SUDOERS_FILE="/etc/sudoers.d/nosleepapp"
    echo "$CONSOLE_USER ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$SUDOERS_FILE.tmp"
    if /usr/sbin/visudo -c -f "$SUDOERS_FILE.tmp" >/dev/null 2>&1; then
        mv "$SUDOERS_FILE.tmp" "$SUDOERS_FILE"
        chmod 0440 "$SUDOERS_FILE"
        chown root:wheel "$SUDOERS_FILE"
    else
        rm -f "$SUDOERS_FILE.tmp"
    fi
    sudo -u "$CONSOLE_USER" open "/Applications/NoSleepApp.app"
fi
exit 0
EOF
chmod +x "$PKG_SCRIPTS/postinstall"

pkgbuild --root "$PKG_ROOT" \
         --scripts "$PKG_SCRIPTS" \
         --identifier com.nosleepapp.pkg \
         --version 2.0.0 \
         --install-location "/" \
         "$ROOT_DIR/NoSleepApp.pkg"

rm -rf "$PKG_ROOT" "$PKG_SCRIPTS"

echo "🎨 4. Applying custom icon to NoSleepApp.pkg..."
if [ -f "$ROOT_DIR/assets/AppIcon.icns" ]; then
    python3 "$SCRIPT_DIR/set_custom_icon.py" "$ROOT_DIR/assets/AppIcon.icns" "$ROOT_DIR/NoSleepApp.pkg"
fi

echo "✅ Distribution packaging complete!"
ls -lh "$ROOT_DIR/NoSleepApp.dmg" "$ROOT_DIR/NoSleepApp.pkg"
echo ""
echo "🔒 Writing Security Checksums (SHA-256)..."
(
    cd "$ROOT_DIR"
    shasum -a 256 NoSleepApp.dmg > NoSleepApp.dmg.sha256
    shasum -a 256 NoSleepApp.pkg > NoSleepApp.pkg.sha256
    shasum -a 256 NoSleepApp.dmg NoSleepApp.pkg > checksums.sha256
    cat checksums.sha256
)
