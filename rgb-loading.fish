# rgb-loading.fish: tell rgb-controller when a long terminal job is running, so the lights show
# the "Loading" profile until it finishes (also when it fails, is Ctrl-C'd or the terminal dies).
#
# Install:   ~/.config/fish/conf.d/rgb-loading.fish   (install.sh does it)
# Customise: set -U rgb_loading_cmds pacman paru yay cachyos-rate-mirrors flatpak topgrade
#
# pacman/paru/yay only count when they actually change something: -S -Syu -U -R ... and a bare
# `paru` / `yay` (which means -Syu). Lookups like -Ss -Si -Q -F stay quiet. Everything else in the
# list (cachyos-rate-mirrors, topgrade, ...) always counts.
# `sudo pacman -Syu` and `doas pacman -Syu` are covered too, because Fish functions do not
# survive `sudo` on their own.
#
# rgb_watch_cmds (default: cachy-update) is different: it opens a short-lived "watch window"
# instead of holding Loading for the whole run. cachy-update is a bash script that spawns
# `sudo pacman -Syu` as a child, which the Fish wrapper never sees, so the daemon watches /proc
# for the real inner pacman and lights Loading only while that pacman actually runs (not during
# the AUR / flatpak / cache / news steps, and never for a pure `-Sy` refresh or a fakeroot build).

status is-interactive; or return

set -q rgb_loading_cmds; or set -g rgb_loading_cmds pacman paru yay cachyos-rate-mirrors
set -q rgb_watch_cmds; or set -g rgb_watch_cmds cachy-update

# __rgb_wants_loading CMD ARGS...   -> status 0 if this invocation should light up "Loading"
function __rgb_wants_loading
    set -l cmd $argv[1]
    set -l args $argv[2..-1]

    switch $cmd
        case pacman paru yay
            if test (count $args) -eq 0
                contains -- $cmd paru yay # bare paru/yay is a full system upgrade
                return
            end
            for a in $args
                switch $a
                    case --search --info --list --groups --print --print-format --query --files --database --deptest --version --help
                        return 1
                end
            end
            for a in $args
                switch $a
                    case --sync --upgrade --remove
                        return 0
                    case '--*'
                        continue
                    case '-*'
                        # short option cluster: its first letter is the operation
                        switch (string sub -s 2 -l 1 -- $a)
                            case S
                                # -Ss -Si -Sl -Sg -Sp -Sc are lookups/cleanups, the rest installs or syncs
                                string match -qr -- '^-S[a-zA-Z]*[silgpc]' $a; and return 1
                                return 0
                            case U R B
                                return 0
                            case '*'
                                return 1
                        end
                end
            end
            return 1
        case '*'
            return 0
    end
end

function __rgb_run
    set -l cmd $argv[1]
    set -l args $argv[2..-1]
    if command -q rgbctl; and __rgb_wants_loading $cmd $args
        rgbctl run loading -- $cmd $args
    else
        command $cmd $args
    end
end

for __rgb_c in $rgb_loading_cmds
    function $__rgb_c --inherit-variable __rgb_c --wraps $__rgb_c --description "$__rgb_c (RGB Loading profile while it runs)"
        __rgb_run $__rgb_c $argv
    end
end
set -e __rgb_c

# rgb_watch_cmds: open a watch window (no Loading hold); the daemon lights Loading only while a
# real inner pacman is running inside the command (used by cachy-update).
function __rgb_watch_run
    set -l cmd $argv[1]
    set -l args $argv[2..-1]
    if command -q rgbctl
        rgbctl watch loading -- $cmd $args
    else
        command $cmd $args
    end
end

for __rgb_w in $rgb_watch_cmds
    function $__rgb_w --inherit-variable __rgb_w --wraps $__rgb_w --description "$__rgb_w (RGB Loading watch window while it runs)"
        __rgb_watch_run $__rgb_w $argv
    end
end
set -e __rgb_w

# sudo / doas: only when the wrapped command comes right after them (`sudo pacman -Syu`)
function __rgb_priv_run
    set -l tool $argv[1]
    set -l rest $argv[2..-1]
    if command -q rgbctl; and test (count $rest) -gt 0; and contains -- $rest[1] $rgb_loading_cmds; and __rgb_wants_loading $rest
        rgbctl run loading -- $tool $rest
    else
        command $tool $rest
    end
end

for __rgb_t in sudo doas
    if command -q $__rgb_t
        function $__rgb_t --inherit-variable __rgb_t --wraps $__rgb_t
            __rgb_priv_run $__rgb_t $argv
        end
    end
end
set -e __rgb_t
