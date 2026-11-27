#!/bin/bash
# update.sh - Update rgb-controller install and remove obsolete files.
# Run with: sudo ./update.sh [--no-pull] [--yes] [--dry-run]

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)." >&2
    echo "Usage: sudo ./update.sh [--no-pull] [--yes] [--dry-run]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=rgb-install-lib.sh
source "$SCRIPT_DIR/rgb-install-lib.sh"

DRY_RUN=0
AUTO_YES=0
NO_PULL=0

usage() {
    echo "Usage: sudo ./update.sh [--no-pull] [--yes] [--dry-run]"
    echo ""
    echo "Options:"
    echo "  --no-pull   Skip 'git pull --ff-only' even inside a git checkout"
    echo "  --yes       Skip confirmation prompt for obsolete file removal"
    echo "  --dry-run   Print what would be removed; make no changes"
    echo "  -h, --help  Show this help"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-pull) NO_PULL=1; shift ;;
        --yes) AUTO_YES=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

acquire_lock

# Tell install.sh (invoked below) that the lock is already held by this process.
export RGB_INSTALL_SKIP_LOCK=1

echo "Updating rgb-controller..."

# 1. Optional git pull
if [[ "$NO_PULL" -eq 0 ]] && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Git checkout at $SCRIPT_DIR"
    echo "Current commit: $(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    git -C "$SCRIPT_DIR" status --short
    if [[ "$AUTO_YES" -eq 1 ]]; then
        echo "Pulling latest changes (--yes)..."
        if ! git -C "$SCRIPT_DIR" pull --ff-only; then
            echo "Error: 'git pull --ff-only' failed (diverged or conflicts). Resolve manually, then re-run." >&2
            release_lock
            exit 1
        fi
    else
        read -rp "Pull latest changes with 'git pull --ff-only'? [y/N] " pull_reply || pull_reply="n"
        if [[ "$pull_reply" == [yY] || "$pull_reply" == [yY][eE][sS] ]]; then
            if ! git -C "$SCRIPT_DIR" pull --ff-only; then
                echo "Error: 'git pull --ff-only' failed (diverged or conflicts). Resolve manually, then re-run." >&2
                release_lock
                exit 1
            fi
        else
            echo "Skipping git pull."
        fi
    fi
else
    echo "Not a git checkout (or --no-pull): skipping git pull."
fi

# 2. Snapshot old manifest before install overwrites it
OLD_MANIFEST="$(mktemp)"
load_manifest "$OLD_MANIFEST"

# 3. Run install (writes the new manifest)
if ! ./install.sh; then
    echo "Error: install.sh failed. Manifest preserved; no files removed." >&2
    rm -f "$OLD_MANIFEST"
    release_lock
    exit 1
fi

# 4. Detect and remove obsolete files
NEW_MANIFEST="$MANIFEST"
find_obsolete "$OLD_MANIFEST" "$NEW_MANIFEST"
if confirm_obsolete; then
    remove_obsolete_files
fi

# 5. Summary
ADDED=0
REMOVED=0
UPDATED=0
if [[ -s "$OLD_MANIFEST" && -s "$NEW_MANIFEST" ]]; then
    ADDED=$(comm -13 "$OLD_MANIFEST" "$NEW_MANIFEST" | wc -l)
    REMOVED=$(comm -23 "$OLD_MANIFEST" "$NEW_MANIFEST" | wc -l)
    UPDATED=$(comm -12 "$OLD_MANIFEST" "$NEW_MANIFEST" | wc -l)
elif [[ -s "$NEW_MANIFEST" ]]; then
    ADDED=$(wc -l < "$NEW_MANIFEST" 2>/dev/null || echo 0)
fi

echo ""
echo "Update complete."
echo "  Files added:    $ADDED"
echo "  Files updated:  $UPDATED"
echo "  Obsolete found: $REMOVED (removed: ${#OBSOLETE_FILES[@]})"

rm -f "$OLD_MANIFEST"
release_lock
