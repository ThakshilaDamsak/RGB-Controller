#!/bin/bash
# install.sh - Install rgb-controller system-wide
# Run with: sudo ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="/usr/local/bin"
SYSTEMD_USER_DIR="/usr/lib/systemd/user"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/scalable/apps"
FISH_DIR="/usr/share/fish/vendor_conf.d"

echo "Installing rgb-controller..."

# Create directories
install -d -m 755 "$BIN_DIR"
install -d -m 755 "$SYSTEMD_USER_DIR"
install -d -m 755 "$DESKTOP_DIR"
install -d -m 755 "$ICON_DIR"
install -d -m 755 "$FISH_DIR"

# Install binaries
echo "Installing binaries to $BIN_DIR..."
install -m 755 "$SCRIPT_DIR/rgb-controller" "$BIN_DIR/rgb-controller"
install -m 755 "$SCRIPT_DIR/rgbctl" "$BIN_DIR/rgbctl"
install -m 755 "$SCRIPT_DIR/rgb-controller-gui" "$BIN_DIR/rgb-controller-gui"
install -m 755 "$SCRIPT_DIR/game-rgb" "$BIN_DIR/game-rgb"

# Install systemd service (replace @BIN@ placeholder)
echo "Installing systemd service..."
sed "s|@BIN@|$BIN_DIR|g" "$SCRIPT_DIR/rgb-controller.service" > "$SYSTEMD_USER_DIR/rgb-controller.service"

# Install desktop files
echo "Installing desktop entries..."
install -m 644 "$SCRIPT_DIR/rgb-controller-gui.desktop" "$DESKTOP_DIR/rgb-controller-gui.desktop"
install -m 644 "$SCRIPT_DIR/rgb-controller-gui-autostart.desktop" "$DESKTOP_DIR/rgb-controller-gui-autostart.desktop"

# Install icon (use the SVG as scalable icon)
echo "Installing icon..."
install -m 644 "$SCRIPT_DIR/rgb-controller.svg" "$ICON_DIR/rgb-controller.svg"

# Update icon cache
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi

# Install fish wrapper
echo "Installing fish wrapper..."
install -m 644 "$SCRIPT_DIR/rgb-loading.fish" "$FISH_DIR/rgb-loading.fish"

# Reload systemd user daemon
echo "Reloading systemd user daemon..."
systemctl --user daemon-reload 2>/dev/null || true

# Enable and start the service for the current user (if running as non-root via sudo)
if [ -n "${SUDO_USER:-}" ]; then
    echo "Enabling service for user $SUDO_USER..."
    sudo -u "$SUDO_USER" systemctl --user enable rgb-controller.service 2>/dev/null || true
    sudo -u "$SUDO_USER" systemctl --user start rgb-controller.service 2>/dev/null || true
    # Enable GUI autostart
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    sudo -u "$SUDO_USER" mkdir -p "$USER_HOME/.config/autostart"
    sudo -u "$SUDO_USER" cp "$SCRIPT_DIR/rgb-controller-gui-autostart.desktop" "$USER_HOME/.config/autostart/rgb-controller-gui-autostart.desktop" 2>/dev/null || true
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Make sure OpenRGB is installed and you have profiles saved:"
echo "     openrgb --save-profile Default"
echo "     openrgb --save-profile Performance"
echo "     openrgb --save-profile Loading"
echo "     openrgb --save-profile Gaming"
echo "     openrgb --save-profile Rainbow"
echo "     openrgb --save-profile Off"
echo ""
echo "  2. The daemon is now running (or will start on next login)."
echo "  3. Open the GUI with: rgb-controller-gui"
echo "  4. Configure your profiles and triggers in the GUI."
echo ""
echo "For Lutris integration:"
echo "  - Pre-launch script: game-rgb start"
echo "  - Post-exit script:  game-rgb stop"
echo ""
echo "For Fish shell (terminal package manager tracking):"
echo "  The fish wrapper is installed. Restart your terminal or run:"
echo "  source /usr/share/fish/vendor_conf.d/rgb-loading.fish"
echo ""
echo "To customize which commands trigger the Loading profile:"
echo "  set -U rgb_loading_cmds pacman paru yay cachyos-rate-mirrors flatpak topgrade"
echo ""
echo "Uninstall with: sudo ./uninstall.sh"