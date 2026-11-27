# RGB Controller

Event-driven OpenRGB profile switcher for Linux. Zero idle CPU, fully configurable via GUI.

> [!CAUTION]
> **Disclaimer: Vibecoded Project**
> 
> This is built for personal use and tested enough to handle my own workflow. It works well for me, though you'll probably run into bugs, weird edge cases, and general jank. Feel free to use it as-is. And if you spot an issue, open a report and I might get around to fixing it. Just don't rely on it for anything that actually matters.

## Features

- **Zero idle overhead** — Pure event-driven (DBus signals, MPRIS, inotify, pidfd). No polling loops.
- **Priority-based profile switching** — AC power > Manual pin > Loading > Gaming > Media > Schedule > Power profile
- **Battery awareness** — Immediately switches to `Off` profile when unplugged; pauses all monitoring.
- **Gaming integration** — `game-rgb` hook for Lutris/Steam (pre-launch / post-exit scripts).
- **Terminal awareness** — Fish wrapper triggers `Loading` profile during `pacman`, `paru`, `yay`, `cachyos-rate-mirrors`, etc.
- **Desktop progress tracking** — KDE JobView, taskbar progress (Unity Launcher), progress notifications.
- **Media detection** — Spotify → `Rainbow`; other media (browser video, mpv, VLC) → `Off` (with configurable delay).
- **Power profile integration** — `power-profiles-daemon`: Balanced → `Default`, Performance → `Performance`, Power-saver → `Default`.
- **Schedule windows** — Time-based profiles (e.g., lights off 23:30–07:00).
- **GUI configuration** — Qt6/PySide6 app, minimizes to tray, daemon runs independently.
- **Per-player media rules** — Map specific players (VLC, mpv, Firefox) to custom profiles.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    rgb-controller (daemon)                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ AC Power │  │ Loading  │  │ Gaming   │  │ Media      │  │
│  │ (UPower) │  │ (DBus    │  │ (Hold    │  │ (MPRIS     │  │
│  │ + sysfs) │  │  monitor)│  │  source) │  │  players)  │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └─────┬──────┘  │
│       │             │             │              │         │
│       └─────────────┴──────┬──────┴──────────────┘         │
│                            ▼                               │
│               ┌───────────────────────┐                    │
│               │   Priority Evaluator  │                    │
│               │  (first match wins)   │                    │
│               └───────────┬───────────┘                    │
│                           ▼                                │
│               ┌───────────────────────┐                    │
│               │    Profile Runner     │                    │
│               │ (openrgb --profile X) │                    │
│               │  retries, timeouts    │                    │
│               └───────────────────────┘                    │
└────────────────────────────────────────────────────────────┘
                              ▲
                ┌─────────────┴─────────────┐
                ▼                           ▼
      ┌───────────────────┐      ┌────────────────────┐
      │   rgbctl (CLI)    │      │ rgb-controller-gui │
      │  status, pin,     │      │  (Qt6, tray,       │
      │  hold, run, log   │      │   live view)       │
      └───────────────────┘      └────────────────────┘
                ▲                           ▲
                │                           │
      ┌─────────┴──────────┐      ┌─────────┴─────────┐
      │  game-rgb (Lutris) │      │  rgb-loading.fish │
      │  start / stop      │      │  pacman, paru,    │
      │  hold for PID      │      │  yay, etc.        │
      └────────────────────┘      └───────────────────┘
```

## Installation

### Quick Install (Arch-based)

```bash
git clone https://github.com/ThakshilaDamsak/RGB-Controller.git
cd RGB-Controller
sudo ./install.sh
```

The install script:
- Installs binaries to `/usr/local/bin/`
- Installs systemd user service (`rgb-controller.service`)
- Installs desktop entries and icon
- Installs Fish shell wrapper (`/usr/share/fish/vendor_conf.d/rgb-loading.fish`)
- Enables and starts the daemon for your user
- Sets up GUI autostart (minimized to tray)

### Manual Install

```bash
# Binaries
sudo install -m 755 rgb-controller rgbctl rgb-controller-gui game-rgb /usr/local/bin/

# Systemd service (adjust path if needed)
sed 's|@BIN@|/usr/local/bin|g' rgb-controller.service | sudo tee /usr/lib/systemd/user/rgb-controller.service

# Desktop entries
sudo install -m 644 rgb-controller-gui.desktop /usr/share/applications/

# Icon
sudo install -m 644 rgb-controller.svg /usr/share/icons/hicolor/scalable/apps/rgb-controller.svg
sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor

# Fish wrapper
sudo install -m 644 rgb-loading.fish /usr/share/fish/vendor_conf.d/

# Reload & enable
systemctl --user daemon-reload
systemctl --user enable --now rgb-controller.service

# GUI autostart (regular desktop entry with --tray)
mkdir -p ~/.config/autostart
sed 's|^Exec=rgb-controller-gui$|Exec=rgb-controller-gui --tray|' rgb-controller-gui.desktop > ~/.config/autostart/rgb-controller-gui.desktop
```

### Requirements

- **OpenRGB** — `pacman -S openrgb` (or flatpak `org.openrgb.OpenRGB`)
- **Python 3.10+** with `python-gobject` (gi) — `pacman -S python-gobject`
- **PySide6** for GUI — `pacman -S pyside6`
- **UPower** — for AC/battery detection (`pacman -S upower`)
- **power-profiles-daemon** — for performance/balanced detection (`pacman -S power-profiles-daemon`)
- **busctl** — for CLI (`pacman -S systemd`)
- **Fish shell** — for terminal wrapper (optional, `pacman -S fish`)

## First Run

1. **Create OpenRGB profiles** (exact names matter):
   ```bash
   openrgb --save-profile Default
   openrgb --save-profile Performance
   openrgb --save-profile Loading
   openrgb --save-profile Gaming
   openrgb --save-profile Rainbow
   openrgb --save-profile Off
   ```
   Profile names are configured in the GUI (Profiles page).

2. **Start the GUI**:
   ```bash
   rgb-controller-gui
   ```
   Or find "RGB Controller" in your application menu.

3. **Configure in GUI**:
   - **Profiles** page: Map each situation to your OpenRGB profile names
   - **Priority** page: Drag to reorder triggers, uncheck to disable
   - **Triggers** page: Configure loading/media detection details
   - **Schedule** page: Add time windows (e.g., night mode)
   - **Timing** page: Adjust debounce, delays, timeouts
   - **Advanced** page: OpenRGB command, daemon control

4. **Verify**:
   ```bash
   rgbctl status
   ```

## Configuration

### Config File

`~/.config/rgb-controller/config.toml` — Only stores values that differ from built-in defaults. The daemon watches this file and applies changes instantly. The GUI writes this file for you.

Example:
```toml
profile_default = "Default"
profile_performance = "Performance"
profile_battery = "Off"
profile_loading = "Loading"
profile_gaming = "Gaming"
profile_spotify = "Rainbow"
profile_other_media = "Off"
priority = ["pin", "loading", "gaming", "media", "schedule", "power"]
debounce_ms = 400
loading_grace_ms = 1500
loading_linger_ms = 3000
media_off_delay_ms = 30000
spotify_hints = ["spotify"]
spotify_beats_other_media = true
watch_jobview = true
watch_launcher = true
watch_notifications = true
watch_proc_pacman = true
proc_scan_ms = 500
ignore_notification_apps = ["Spotify"]
openrgb_cmd = ["openrgb", "--client", "localhost:6742"]
```

### Priority Order (highest first)

1. **pin** — Manual override from GUI or `rgbctl pin`
2. **loading** — Desktop progress bars, terminal package jobs
3. **gaming** — `game-rgb start` (Lutris/Steam)
4. **media** — Spotify (`Rainbow`), other media (`Off` after delay)
5. **schedule** — Time windows
6. **power** — power-profiles-daemon mode (Balanced/Performance/Power-saver)

AC power is a **hard gate**: on battery → `Off` profile, everything else paused.

### Media OFF Delay

When non-Spotify media starts playing (browser video, mpv, VLC), the daemon waits **30 seconds** (default, configurable) before switching to the `Off` profile. This prevents lights from flickering when scrolling past videos on media-heavy sites.

- **Spotify is immediate** — No delay, switches to `Rainbow` instantly.
- **Customizable** — GUI → Timing page → "Media OFF delay" (0 = instant, up to 5 minutes).
- **If Spotify starts during delay** — Delay cancels, switches to `Rainbow` immediately.
- **If media stops during delay** — Delay cancels, no profile change.

### Per-Player Media Rules

GUI → Triggers page → "Per-player profiles". First match wins, beats the Spotify rule.

Example:
- Player contains `vlc` → Profile `VLC Colors`
- Player contains `mpv` → Profile `Off`
- Player contains `firefox` → Profile `Dim`

Player names are the part after `org.mpris.MediaPlayer2.` (see Live page for running players).

## Usage

### CLI (`rgbctl`)

```bash
rgbctl status              # Current state and why
rgbctl status --raw        # Raw JSON
rgbctl pin Gaming 30m      # Force Gaming for 30 minutes
rgbctl pin Gaming          # Force Gaming until unpinned
rgbctl unpin               # Remove manual pin
rgbctl reload              # Reload config.toml
rgbctl reevaluate          # Re-apply current profile
rgbctl log                 # Recent daemon log lines
rgbctl hold loading pkg-123 1234  # Manual hold (source, token, PID)
rgbctl release loading pkg-123
rgbctl run loading -- pacman -Syu  # Hold while command runs
rgbctl watch loading -- cachy-update  # Watch window: light Loading only while the inner pacman runs
rgbctl gui                 # Open GUI
```

### Lutris / Steam Integration

**Recommended (wrapper mode — no pre/post scripts needed):**

**Lutris:** Game configuration → System options → **Command prefix**: `game-rgb run`

**Steam:** Right-click game → Properties → Launch Options: `game-rgb run %command%`

The `game-rgb run` command wraps the game executable. It creates a hold tied to the game's PID and auto-releases on exit (via shell trap + daemon pidfd watch). Works like `game-performance` from CachyOS.

**Legacy (pre/post scripts — still works):**

**Lutris:**
- Pre-launch script: `game-rgb start`
- Post-exit script: `game-rgb stop`

The legacy mode stores the token in `$XDG_RUNTIME_DIR/rgb-game-token` so `stop` can release the correct hold even though it runs in a different process.

### Fish Shell Wrapper

Automatically triggers `Loading` profile for:
- `pacman`, `paru`, `yay` (only install/update/remove operations, not queries)
- `cachyos-rate-mirrors`, `flatpak`, `topgrade` (always)
- `sudo pacman -Syu`, `doas paru` (wraps sudo/doas)

Customize:
```fish
set -U rgb_loading_cmds pacman paru yay cachyos-rate-mirrors flatpak topgrade
```

**`cachy-update` watch window:** `cachy-update` is in a separate list (`rgb_watch_cmds`, default
`cachy-update`) because it must **not** hold `Loading` for its whole run. Instead the wrapper opens
a short-lived *watch window* and the daemon scans `/proc` for the **real inner `pacman`** (the
`sudo pacman -Syu` step), lighting `Loading` only while that pacman actually runs — off again
during the AUR / flatpak / cache / news steps. Pure refresh (`-Sy`), queries (`-Ss`, `-Q`, ...) and
fakeroot-driven pacman never count. Customize with `set -U rgb_watch_cmds cachy-update`.

### GUI Tray Behavior

- **Close window** → Minimizes to tray (daemon keeps running)
- **Tray icon** → Shows current profile color (configurable)
- **Tray menu** → Quick pin profiles, open OpenRGB, quit GUI only
- **Quit from tray** → Exits GUI, daemon continues

## Advanced

### Run OpenRGB Server (Faster Profile Switching)

```bash
# Terminal 1 (keep running):
openrgb --server

# In GUI → Advanced → "Use a running OpenRGB server (faster)"
# or set in config.toml:
openrgb_cmd = ["openrgb", "--client", "localhost:6742"]
```

### Add Custom Trigger (Developer)

```python
# In rgb-controller, add a new Source subclass:
class CameraSource(Source):
    name = "camera"
    def start(self):
        # Subscribe to camera events, call self.ctl.schedule() on change
    def wanted(self):
        return PROFILE_CAMERA if self.active else None

SOURCES["camera"] = CameraSource
# Add "camera" to PRIORITY tuple
```

### Debugging

```bash
# Daemon logs
rgbctl log

# Live status
rgbctl status

# Test OpenRGB command
rgbctl pin Rainbow 10s

# Check if daemon is running
systemctl --user status rgb-controller.service
journalctl --user -u rgb-controller.service -f
```

## Uninstall

```bash
sudo ./uninstall.sh
```

Removes binaries, systemd service, desktop entries, icon, fish wrapper. Keeps user config in `~/.config/rgb-controller/`.

## Update

```bash
sudo ./update.sh
```

`update.sh` reinstalls the current release (optionally pulling `git pull --ff-only` first when run inside the git checkout), then detects and removes files that a previous version installed but the current release no longer ships (e.g. the legacy `rgb-controller-gui-autostart.desktop`). It records what it installs in `/var/lib/rgb-controller/installed-files.txt` so obsolete files can be detected on future updates.

Options:
- `--no-pull` — skip the git pull step
- `--yes` — skip the obsolete-file confirmation prompt
- `--dry-run` — print what would be removed without making changes

Obsolete file removal is interactive by default (`[y/N]`) and only touches files under known install prefixes (`/usr/local/bin`, `/usr/share/applications`, `/usr/share/icons/...`, `/usr/share/fish/vendor_conf.d`, `/usr/lib/systemd/user`).

## File Overview

| File | Purpose |
|------|---------|
| `rgb-controller` | Main daemon (Python, GLib/DBus) |
| `rgbctl` | CLI client (shell, busctl) |
| `rgb-controller-gui` | Qt6 GUI (PySide6) |
| `game-rgb` | Lutris/Steam hook script |
| `rgb-loading.fish` | Fish shell wrapper for package managers |
| `rgb-controller.service` | Systemd user service |
| `rgb-controller-gui.desktop` | App menu entry |
| `rgb-controller-gui-autostart.desktop` | Tray autostart |
| `rgb-controller.svg` | App icon |
| `install.sh` / `uninstall.sh` / `update.sh` | Install/uninstall/update scripts |
| `rgb-install-lib.sh` | Shared library sourced by the scripts (not installed) |

## License

MIT — Do whatever you want, but keep the license notice.
