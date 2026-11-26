#!/bin/bash
# uninstall.sh - Remove rgb-controller system-wide
# Run with: sudo ./uninstall.sh

set -euo pipefail

# Check for root/sudo
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)." >&2
    echo "Usage: sudo ./uninstall.sh" >&2
    exit 1
fi

BIN_DIR="/usr/local/bin"
SYSTEMD_USER_DIR="/usr/lib/systemd/user"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/scalable/apps"
FISH_DIR="/usr/share/fish/vendor_conf.d"

echo "Uninstalling rgb-controller..."

# Stop and disable service for current user (if running via sudo)
if [ -n "${SUDO_USER:-}" ]; then
    echo "Stopping service for user $SUDO_USER..."
    sudo -u "$SUDO_USER" systemctl --user stop rgb-controller.service 2>/dev/null || true
    sudo -u "$SUDO_USER" systemctl --user disable rgb-controller.service 2>/dev/null || true
    # Remove GUI autostart
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    sudo -u "$SUDO_USER" rm -f "$USER_HOME/.config/autostart/rgb-controller-gui-autostart.desktop" "$USER_HOME/.config/autostart/rgb-controller-gui.desktop" 2>/dev/null || true
fi

# Remove binaries
echo "Removing binaries..."
rm -f "$BIN_DIR/rgb-controller"
rm -f "$BIN_DIR/rgbctl"
rm -f "$BIN_DIR/rgb-controller-gui"
rm -f "$BIN_DIR/game-rgb"

# Remove systemd service
echo "Removing systemd service..."
rm -f "$SYSTEMD_USER_DIR/rgb-controller.service"

# Remove desktop files
echo "Removing desktop entries..."
rm -f "$DESKTOP_DIR/rgb-controller-gui.desktop"
rm -f "$DESKTOP_DIR/rgb-controller-gui-autostart.desktop"

# Remove icon
echo "Removing icon..."
rm -f "$ICON_DIR/rgb-controller.svg"

# Update icon cache
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi

# Remove fish wrapper
echo "Removing fish wrapper..."
rm -f "$FISH_DIR/rgb-loading.fish"

# Reload systemd user daemon
systemctl --user daemon-reload 2>/dev/null || true

echo ""
echo "Uninstallation complete!"
echo ""
echo "Note: User config files in ~/.config/rgb-controller/ were not removed."
echo "Remove them manually if desired: rm -rf ~/.config/rgb-controller/"