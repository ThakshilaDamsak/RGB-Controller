#!/bin/bash
# install.sh - Install rgb-controller system-wide
# Run with: sudo ./install.sh

set -euo pipefail

# Check for root/sudo
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)." >&2
    echo "Usage: sudo ./install.sh" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared library (constants, locking, manifest, obsolete logic)
# shellcheck source=rgb-install-lib.sh
source "$SCRIPT_DIR/rgb-install-lib.sh"

acquire_lock

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

    # Enable and start the service for the current user (if running as non-root via sudo).
    # systemctl --user needs the target user's XDG_RUNTIME_DIR to reach their systemd
    # instance; sudo scrubs it, so we pass it explicitly. Do NOT silence failures: a
    # failed enable/restart means the daemon won't autostart and users deserve to know.
    if [ -n "${SUDO_USER:-}" ]; then
        USER_UID=$(id -u "$SUDO_USER")
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

        echo "Enabling service for user $SUDO_USER..."
        if ! sudo -u "$SUDO_USER" env XDG_RUNTIME_DIR="/run/user/$USER_UID" \
            systemctl --user enable rgb-controller.service; then
            echo "Warning: could not enable rgb-controller.service for $SUDO_USER" >&2
            echo "  Autostart on login may not work; enable manually: systemctl --user enable rgb-controller.service" >&2
        fi

        echo "Starting service for user $SUDO_USER..."
        if ! sudo -u "$SUDO_USER" env XDG_RUNTIME_DIR="/run/user/$USER_UID" \
            systemctl --user restart rgb-controller.service; then
            echo "Warning: could not start rgb-controller.service for $SUDO_USER" >&2
            echo "  The daemon will start automatically on your next graphical-session login," >&2
            echo "  or start it manually with: systemctl --user start rgb-controller.service" >&2
        fi

        # Restart the GUI (if running) so it picks up the renamed D-Bus name.
        # rgb-controller-gui reads SERVICE/OBJ_PATH/IFACE at startup; a running
        # instance keeps the old name until restarted. Best-effort only: never
        # fail the install over a user-session GUI we can't reach.
        if pgrep -u "$SUDO_USER" -x "rgb-controller-gui" >/dev/null 2>&1; then
            echo "Restarting rgb-controller-gui for user $SUDO_USER (new D-Bus name)..."
            pkill -TERM -u "$SUDO_USER" -x "rgb-controller-gui" 2>/dev/null || true
            sleep 1
            sudo -u "$SUDO_USER" env XDG_RUNTIME_DIR="/run/user/$USER_UID" \
                bash -c 'nohup rgb-controller-gui --tray >/dev/null 2>&1 &' 2>/dev/null || true
            echo "  (If it did not relaunch, start it manually: rgb-controller-gui --tray)"
        fi

    # Remove known-legacy autostart to prevent double GUI launch on upgrade
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    sudo -u "$SUDO_USER" rm -f "$USER_HOME/.config/autostart/rgb-controller-gui-autostart.desktop" 2>/dev/null || true
    # Enable GUI autostart (regular desktop entry with --tray)
    sudo -u "$SUDO_USER" mkdir -p "$USER_HOME/.config/autostart"
    sed 's|^Exec=rgb-controller-gui$|Exec=rgb-controller-gui --tray|' "$SCRIPT_DIR/rgb-controller-gui.desktop" > "$USER_HOME/.config/autostart/rgb-controller-gui.desktop"
    chown "$SUDO_USER" "$USER_HOME/.config/autostart/rgb-controller-gui.desktop"
fi

# Record manifest of installed system files
record_manifest
release_lock

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
echo "For Lutris integration (recommended - wrapper mode, like game-performance):"
echo "  Game config → System options → Command prefix:  game-rgb run"
echo ""
echo "For Steam:"
echo "  Properties → Launch Options:  game-rgb run %command%"
echo ""
echo "(Legacy pre/post scripts still work: game-rgb start / game-rgb stop)"
echo ""
echo "For Fish shell (terminal package manager tracking):"
echo "  The fish wrapper is installed. Restart your terminal or run:"
echo "  source /usr/share/fish/vendor_conf.d/rgb-loading.fish"
echo ""
echo "To customize which commands trigger the Loading profile:"
echo "  set -U rgb_loading_cmds pacman paru yay cachyos-rate-mirrors flatpak topgrade"
echo ""
echo "cachy-update uses a watch window (rgb_watch_cmds): only its real inner pacman"
echo "lights Loading, detected automatically by the daemon (no wrapper changes needed)."
echo ""
echo "Media OFF delay (prevents flicker when scrolling past videos):"
echo "  GUI → Timing page → \"Media OFF delay\" (default 30s, set 0 for instant)"
echo ""
echo "Uninstall with: sudo ./uninstall.sh"