#!/bin/bash
# uninstall.sh - Remove rgb-controller system-wide
# Run with: sudo ./uninstall.sh

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)." >&2
    echo "Usage: sudo ./uninstall.sh" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=rgb-install-lib.sh
source "$SCRIPT_DIR/rgb-install-lib.sh"

acquire_lock

echo "Uninstalling rgb-controller..."

# Stop and disable service for current user (if running via sudo)
if [ -n "${SUDO_USER:-}" ]; then
    echo "Stopping service for user $SUDO_USER..."
    USER_UID=$(id -u "$SUDO_USER")
    # systemctl --user needs the target user's XDG_RUNTIME_DIR; sudo scrubs it.
    if ! sudo -u "$SUDO_USER" env XDG_RUNTIME_DIR="/run/user/$USER_UID" \
        systemctl --user stop rgb-controller.service; then
        echo "Warning: could not stop rgb-controller.service for $SUDO_USER" >&2
    fi
        if ! sudo -u "$SUDO_USER" env XDG_RUNTIME_DIR="/run/user/$USER_UID" \
            systemctl --user disable rgb-controller.service; then
            echo "Warning: could not disable rgb-controller.service for $SUDO_USER" >&2
        fi
        # Stop the GUI (if running) so it doesn't keep trying to reach the
        # removed daemon; best-effort, never fails uninstall.
        if pgrep -u "$SUDO_USER" -x "rgb-controller-gui" >/dev/null 2>&1; then
            echo "Stopping rgb-controller-gui for user $SUDO_USER..."
            pkill -TERM -u "$SUDO_USER" -x "rgb-controller-gui" 2>/dev/null || true
        fi
        # Remove GUI autostart (current + legacy)
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    sudo -u "$SUDO_USER" rm -f "$USER_HOME/.config/autostart/rgb-controller-gui-autostart.desktop" "$USER_HOME/.config/autostart/rgb-controller-gui.desktop" 2>/dev/null || true
fi

removed_icon=0

# Remove a single path if it is under an allowed install prefix.
remove_path() {
    local p="$1"
    if is_allowed_path "$p"; then
        rm -f "$p"
        if [[ "$p" == "$ICON_DIR"/* ]]; then
            removed_icon=1
        fi
    fi
}

if [[ -f "$MANIFEST" ]]; then
    echo "Removing files listed in manifest..."
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        remove_path "$p"
    done < "$MANIFEST"
else
    echo "No manifest found: removing known files..."
    remove_path "$BIN_DIR/rgb-controller"
    remove_path "$BIN_DIR/rgbctl"
    remove_path "$BIN_DIR/rgb-controller-gui"
    remove_path "$BIN_DIR/game-rgb"
    remove_path "$SYSTEMD_USER_DIR/rgb-controller.service"
    remove_path "$DESKTOP_DIR/rgb-controller-gui.desktop"
    remove_path "$ICON_DIR/rgb-controller.svg"
    remove_path "$FISH_DIR/rgb-loading.fish"
fi

# Also remove the known-legacy system desktop file
remove_path "$DESKTOP_DIR/rgb-controller-gui-autostart.desktop"

# Remove manifest (+ directory if now empty)
rm -f "$MANIFEST"
rmdir "$MANIFEST_DIR" 2>/dev/null || true

# Refresh icon cache only if an icon was actually removed
if [[ "$removed_icon" -eq 1 ]] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi

# Reload systemd user daemon
systemctl --user daemon-reload 2>/dev/null || true

release_lock

echo ""
echo "Uninstallation complete!"
echo ""
echo "Note: User config files in ~/.config/rgb-controller/ were not removed."
echo "Remove them manually if desired: rm -rf ~/.config/rgb-controller/"
