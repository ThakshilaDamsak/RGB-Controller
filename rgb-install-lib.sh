#!/bin/bash
# rgb-install-lib.sh - Shared library for rgb-controller install/update/uninstall.
# Source this file from install.sh, update.sh, uninstall.sh. Do not execute directly.
# This file intentionally does NOT call 'set -e'; callers keep their own error handling.

# --- Path constants ---
BIN_DIR="/usr/local/bin"
SYSTEMD_USER_DIR="/usr/lib/systemd/user"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/scalable/apps"
FISH_DIR="/usr/share/fish/vendor_conf.d"
MANIFEST_DIR="/var/lib/rgb-controller"
MANIFEST="$MANIFEST_DIR/installed-files.txt"
LOCK="$MANIFEST_DIR/install.lock"

# Prefixes under which removal is permitted (defense in depth).
ALLOWED_PREFIXES=(
    "$BIN_DIR"
    "$SYSTEMD_USER_DIR"
    "$DESKTOP_DIR"
    "$ICON_DIR"
    "$FISH_DIR"
)

# Known historical files always treated as obsolete (system-level; the per-user
# legacy autostart is handled explicitly by install.sh/uninstall.sh).
RGB_LEGACY_OBSOLETE=(
    "$DESKTOP_DIR/rgb-controller-gui-autostart.desktop"
)

# Canonical system files installed by install.sh (manifest contents).
INSTALLED_SYSTEM_FILES=(
    "$BIN_DIR/rgb-controller"
    "$BIN_DIR/rgbctl"
    "$BIN_DIR/rgb-controller-gui"
    "$BIN_DIR/game-rgb"
    "$SYSTEMD_USER_DIR/rgb-controller.service"
    "$DESKTOP_DIR/rgb-controller-gui.desktop"
    "$ICON_DIR/rgb-controller.svg"
    "$FISH_DIR/rgb-loading.fish"
)

# Lock state
_LOCK_HELD=0
LOCK_FD=""

# --- Helpers ---
is_allowed_path() {
    local path="$1" prefix
    for prefix in "${ALLOWED_PREFIXES[@]}"; do
        if [[ "$path" == "$prefix" || "$path" == "$prefix"/* ]]; then
            return 0
        fi
    done
    return 1
}

is_under_icon_dir() {
    [[ "$1" == "$ICON_DIR"/* ]]
}

# --- Locking ---
# Acquire an exclusive, non-blocking flock on $LOCK. When RGB_INSTALL_SKIP_LOCK=1
# is exported by the caller (update.sh), locking is skipped because the caller
# already holds the lock across the install + obsolete cleanup sequence.
acquire_lock() {
    if [[ "${RGB_INSTALL_SKIP_LOCK:-0}" == "1" ]]; then
        _LOCK_HELD=1
        return 0
    fi
    if [[ "$_LOCK_HELD" -eq 1 ]]; then
        return 0
    fi
    mkdir -p "$MANIFEST_DIR"
    exec {LOCK_FD}>"$LOCK"
    if ! flock -n "$LOCK_FD"; then
        echo "Error: Another rgb-controller install/update is already running." >&2
        exit 1
    fi
    _LOCK_HELD=1
}

release_lock() {
    if [[ "${RGB_INSTALL_SKIP_LOCK:-0}" == "1" ]]; then
        _LOCK_HELD=0
        return 0
    fi
    if [[ "$_LOCK_HELD" -ne 1 ]]; then
        return 0
    fi
    flock -u "$LOCK_FD" 2>/dev/null || true
    exec {LOCK_FD}>&- 2>/dev/null || true
    _LOCK_HELD=0
}

# --- Manifest ---
# Atomically write the current install's file list to the manifest (temp + mv),
# sorted, one absolute path per line. The manifest file itself is never listed.
record_manifest() {
    local files=()
    if [[ $# -gt 0 ]]; then
        files=("$@")
    else
        files=("${INSTALLED_SYSTEM_FILES[@]}")
    fi
    mkdir -p "$MANIFEST_DIR"
    local tmp="$MANIFEST.tmp.$$"
    : > "$tmp"
    local f
    for f in "${files[@]}"; do
        [[ -n "$f" ]] && echo "$f" >> "$tmp"
    done
    LC_ALL=C sort -u "$tmp" -o "$tmp"
    mv -f "$tmp" "$MANIFEST"
}

# Read the current manifest into $1 (sorted), or create an empty file if missing.
load_manifest() {
    local out="$1"
    if [[ -f "$MANIFEST" ]]; then
        LC_ALL=C sort -u "$MANIFEST" > "$out"
    else
        : > "$out"
    fi
}

# --- Obsolete detection ---
# Populate OBSOLETE_FILES with validated paths present in the old manifest but
# missing from the new one, unioned with RGB_LEGACY_OBSOLETE (filtered to paths
# that exist and pass the allowed-prefix check).
find_obsolete() {
    local old_manifest="$1"
    local new_manifest="$2"
    local tmp
    tmp="$(mktemp)"
    if [[ -s "$old_manifest" ]]; then
        comm -23 "$old_manifest" "$new_manifest" > "$tmp" 2>/dev/null || true
    fi
    local f
    for f in "${RGB_LEGACY_OBSOLETE[@]}"; do
        if [[ -f "$f" ]]; then
            echo "$f" >> "$tmp"
        fi
    done
    OBSOLETE_FILES=()
    if [[ -s "$tmp" ]]; then
        LC_ALL=C sort -u "$tmp" -o "$tmp"
        local path
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            if is_allowed_path "$path"; then
                OBSOLETE_FILES+=("$path")
            fi
        done < "$tmp"
    fi
    rm -f "$tmp"
}

# --- Obsolete confirmation ---
# Returns 0 if removal should proceed, 1 otherwise. Honors DRY_RUN and AUTO_YES.
confirm_obsolete() {
    if [[ ${#OBSOLETE_FILES[@]} -eq 0 ]]; then
        return 0
    fi
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        echo "The following files would be removed (dry run, no changes made):"
        local f
        for f in "${OBSOLETE_FILES[@]}"; do
            echo "  - $f"
        done
        return 0
    fi
    if [[ "${AUTO_YES:-0}" -eq 1 ]]; then
        return 0
    fi
    echo "The following files were installed by an earlier version of rgb-controller but are"
    echo "no longer part of the current release. They are safe to remove:"
    local f
    for f in "${OBSOLETE_FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
    local reply
    if ! read -rp "Remove these obsolete files? [y/N] " reply; then
        reply="n"
    fi
    [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]
}

# --- Obsolete removal ---
# rm -f the confirmed, validated paths; refresh icon cache only if an icon was removed.
remove_obsolete_files() {
    local removed_icon=0 f
    for f in "${OBSOLETE_FILES[@]}"; do
        rm -f "$f"
        if is_under_icon_dir "$f"; then
            removed_icon=1
        fi
    done
    if [[ "$removed_icon" -eq 1 ]] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
    fi
}
