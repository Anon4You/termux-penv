#!/data/data/com.termux/files/usr/bin/bash

# Shared login and run handling for termux-penv environments.
# Expects: LOGIN_ENV, LOGIN_PREFIX, LOGIN_BASE
# Optional: LOGIN_PROG, LOGIN_RUN, LOGIN_USAGE_CMD

BLUE='\033[1;34m'
NC='\033[0m'

. "$(dirname "${BASH_SOURCE[0]}")/env-common.sh"

login_usage() {
    local code="${1:-1}"
    local prog="${LOGIN_PROG:-termux-penv}"
    cat <<EOF
Usage: $prog ${LOGIN_USAGE_CMD:-login} <environment> [options] [command]

Options:
  -h, --help              Show this help.
  -P, --redirect-ports    Replace privileged port bindings with higher ports.
  --isolated              Do not bind /storage, /sbin or /root.
  --minimal               Isolated mode without System V IPC. The Android
                          runtime paths (/system, /apex, /vendor) stay bound.
  --shared-home           Bind Termux home to /home inside the chroot.
  --shared-tmp            Bind the Termux tmp directory to /tmp.
  --shared-x11            Bind the Termux X11 socket directory to /tmp/.X11-unix.
  -b, --bind SRC:DEST     Custom filesystem binding. Can be repeated.
  --no-link2symlink       Disable hardlink emulation by proot.
  --no-sysvipc            Disable System V IPC emulation.
  --no-kill-on-exit       Hang until all session processes exit.
  --qemu                  Use QEMU even for a native architecture (diagnostic).
                          QEMU must already be installed; it is never auto-installed.
  --emulator FILE         Custom QEMU user-mode emulator binary (diagnostic).
  --kernel TEXT           Kernel release string reported by uname.
  -w, --work-dir PATH     Initial working directory.
  -e, --env VAR=VALUE     Set an environment variable. Can be repeated.
  -d, --detach            Start a command in the background and return.
  --get-proot-cmd         Print the proot command and exit.
  --arch ARCH             Chroot architecture: aarch64, arm, x86_64 or i686.
                          Default: this device's arch, or the only installed one.

Environment: ${LOGIN_ENV:-<environment>}
By default the chroot uses its own private home; use --shared-home for Termux home.
EOF
    exit "$code"
}

find_emulator() {
    local bin
    for bin in "$1" "$1-static"; do
        if command -v "$bin" >/dev/null 2>&1; then
            command -v "$bin"
            return 0
        fi
    done
    return 1
}

login_main() {
    local shared_home=0 shared_tmp=0 shared_x11=0 isolated=0 minimal=0
    local link2symlink=1 sysvipc=1 kill_on_exit=1 redirect_ports=0 detach=0 get_cmd=0
    local use_qemu=0
    local emulator="" kernel="" workdir="" arch_spec=""
    local -a binds=() envs=() cmd=() args=() run=() cmd_env=()
    local host_home="${HOME:-$PREFIX/../home}"
    local host_tmp="${TMPDIR:-$PREFIX/tmp}"
    local b e f guest_arch host_arch qemu_bin qemu_pkg

    if [ ! -x "$PREFIX/bin/proot" ]; then
        echo "ERROR: proot not found. Install it with 'pkg install proot'"
        exit 1
    fi

    unset LD_PRELOAD

    while [ $# -gt 0 ]; do
        case "$1" in
            --bind=*|--emulator=*|--kernel=*|--work-dir=*|--env=*|--arch=*)
                set -- "${1%%=*}" "${1#*=}" "${@:2}" ;;
        esac
        case "$1" in
            -h|--help) login_usage 0 ;;
            -P|--redirect-ports) redirect_ports=1; shift ;;
            --isolated) isolated=1; shift ;;
            --minimal) minimal=1; isolated=1; shift ;;
            --shared-home) shared_home=1; shift ;;
            --shared-tmp) shared_tmp=1; shift ;;
            --shared-x11) shared_x11=1; shared_tmp=1; shift ;;
            -b|--bind) [ $# -ge 2 ] && [ -n "$2" ] || { echo "ERROR: --bind needs SRC:DEST." >&2; login_usage 1; }
                       binds+=("$2"); shift 2 ;;
            --no-link2symlink) link2symlink=0; shift ;;
            --no-sysvipc) sysvipc=0; shift ;;
            --no-kill-on-exit) kill_on_exit=0; shift ;;
            --qemu) use_qemu=1; shift ;;
            --emulator) [ $# -ge 2 ] && [ -n "$2" ] || { echo "ERROR: --emulator needs a file." >&2; login_usage 1; }
                        emulator="$2"; shift 2 ;;
            --kernel) [ $# -ge 2 ] || login_usage; kernel="$2"; shift 2 ;;
            -w|--work-dir) [ $# -ge 2 ] || login_usage; workdir="$2"; shift 2 ;;
            -e|--env) [ $# -ge 2 ] || login_usage; envs+=("$2"); shift 2 ;;
            -d|--detach) detach=1; shift ;;
            --get-proot-cmd) get_cmd=1; shift ;;
            --arch) [ $# -ge 2 ] && [ -n "$2" ] || { echo "ERROR: --arch needs a value." >&2; login_usage 1; }
                    arch_spec="$2"; shift 2 ;;
            --) shift; cmd=("$@"); break ;;
            -*) echo "ERROR: Unknown option '$1'." >&2; login_usage 1 ;;
            *) cmd=("$@"); break ;;
        esac
    done

    if [ "$minimal" -eq 1 ]; then
        sysvipc=0
    fi

    if [ "${LOGIN_RUN:-0}" -eq 1 ] && [ ${#cmd[@]} -eq 0 ]; then
        echo "ERROR: run needs a command (for example: termux-penv run $LOGIN_ENV uname -m)." >&2
        exit 1
    fi

    if [ "$detach" -eq 1 ] && [ ${#cmd[@]} -eq 0 ]; then
        echo "ERROR: --detach needs a command (for example: termux-penv login $LOGIN_ENV -d -- sleep 60)." >&2
        exit 1
    fi

    case "$workdir" in
        ''|/*) ;;
        *) echo "ERROR: --work-dir must be an absolute path inside the chroot." >&2; exit 1 ;;
    esac

    resolve_arch "$arch_spec"
    LOGIN_NEWROOT="$LOGIN_BASE/$LOGIN_PREFIX-$RESOLVED_ARCH/usr"
    if [ ! -d "$LOGIN_NEWROOT" ]; then
        echo "ERROR: $LOGIN_ENV ($RESOLVED_ARCH) is not installed." >&2
        echo "Install it with: termux-penv install $LOGIN_ENV --arch $RESOLVED_ARCH" >&2
        exit 1
    fi
    if [ -L "$LOGIN_NEWROOT" ]; then
        echo "ERROR: $LOGIN_ENV ($RESOLVED_ARCH) has a symlinked usr directory; reinstall it." >&2
        exit 1
    fi
    guest_arch="$RESOLVED_ARCH"
    host_arch=$(uname -m)

    case "$host_arch:$guest_arch" in
        aarch64:aarch64|aarch64:arm|arm*:arm|x86_64:x86_64|x86_64:i686|i686:i686) ;;
        *)
            echo "ERROR: $LOGIN_ENV ($guest_arch) cannot run on this $host_arch device." >&2
            echo "Termux binaries use Android's host-architecture /system/bin/linker64," >&2
            echo "so QEMU cannot supply the $guest_arch linker they need." >&2
            echo "Use a native architecture, or use proot-distro for a cross-architecture Linux distribution." >&2
            exit 1
            ;;
    esac

    if [ "$get_cmd" -eq 0 ] && [ "${LOGIN_RUN:-0}" -ne 1 ]; then
        echo -e "${BLUE}Logging into $LOGIN_ENV ($RESOLVED_ARCH)...${NC}" >&2
    fi

    if [ "$use_qemu" -eq 1 ] && [ -z "$emulator" ]; then
        case "$guest_arch" in
            aarch64) qemu_bin=qemu-aarch64; qemu_pkg=qemu-user-aarch64 ;;
            arm) qemu_bin=qemu-arm; qemu_pkg=qemu-user-arm ;;
            x86_64) qemu_bin=qemu-x86_64; qemu_pkg=qemu-user-x86-64 ;;
            i686) qemu_bin=qemu-i386; qemu_pkg=qemu-user-i386 ;;
            *) qemu_bin=""; qemu_pkg="" ;;
        esac
        if [ -z "$qemu_bin" ] || ! emulator=$(find_emulator "$qemu_bin"); then
            echo "ERROR: QEMU for $guest_arch is not installed." >&2
            echo "Install it first with: pkg install $qemu_pkg" >&2
            exit 1
        fi
        echo "NOTE: Using $emulator for $guest_arch" >&2
    fi

    [ "$kill_on_exit" -eq 1 ] && args+=(--kill-on-exit)
    [ "$link2symlink" -eq 1 ] && args+=(--link2symlink)
    [ "$sysvipc" -eq 1 ] && args+=(--sysvipc)
    [ "$redirect_ports" -eq 1 ] && args+=(-p)
    [ -n "$kernel" ] && args+=(-k "$kernel")
    if [ -n "$emulator" ]; then
        [ -x "$emulator" ] || { echo "ERROR: emulator '$emulator' is not executable" >&2; exit 1; }
        args+=(-q "$emulator")
    fi

    if [ "$isolated" -eq 0 ]; then
        if [ -d /sbin ] && [ -d /root ]; then
            args+=(-b /sbin:/sbin -b /root:/root)
        fi
        [ -d /storage ] && args+=(-b /storage:/storage)
    fi

    [ -d /system ] && args+=(-b /system:/system)
    [ -d /vendor ] && args+=(-b /vendor:/vendor)
    [ -d /apex ] && args+=(-b /apex:/apex)
    [ -e /linkerconfig/ld.config.txt ] && args+=(-b /linkerconfig/ld.config.txt:/linkerconfig/ld.config.txt)
    [ -f /property_contexts ] && args+=(-b /property_contexts:/property_contexts)

    args+=(-b "$LOGIN_NEWROOT:/data/data/com.termux/files/usr/")
    args+=(-b "$LOGIN_NEWROOT:/usr")
    for f in bin etc lib share tmp var; do
        if [ -e "$LOGIN_NEWROOT/$f" ] && [ ! -L "$LOGIN_NEWROOT/$f" ]; then
            args+=(-b "$LOGIN_NEWROOT/$f:/$f")
        fi
    done

    args+=(-b /dev:/dev -b /proc:/proc)
    [ -d /sys ] && args+=(-b /sys:/sys)
    args+=(-r "$LOGIN_NEWROOT/..")

    [ "$shared_home" -eq 1 ] && args+=(-b "$host_home:/home")
    [ "$shared_tmp" -eq 1 ] && args+=(-b "$host_tmp:/tmp")
    if [ "$shared_x11" -eq 1 ]; then
        if [ -d "$host_tmp/.X11-unix" ]; then
            args+=(-b "$host_tmp/.X11-unix:/tmp/.X11-unix")
        else
            echo "WARNING: $host_tmp/.X11-unix not found; skipping X11 bind" >&2
        fi
    fi

    for b in "${binds[@]}"; do
        args+=(-b "$b")
    done

    export HOME=/home
    for e in "${envs[@]}"; do
        case "$e" in
            *=*) export "$e" || exit 1 ;;
            *) echo "ERROR: --env expects VAR=VALUE, got '$e'" >&2; exit 1 ;;
        esac
    done

    args+=(--cwd="${workdir:-/home}")
    if [ ${#cmd[@]} -eq 0 ]; then
        run=(bash -c '/usr/bin/login')
    else
        run=("${cmd[@]}")
    fi

    if [ "$get_cmd" -eq 1 ]; then
        cmd_env=(env -u LD_PRELOAD "HOME=/home")
        cmd_env+=("${envs[@]}")
        printf '%q ' "${cmd_env[@]}" "$PREFIX/bin/proot" "${args[@]}" "${run[@]}"
        printf '\n'
        exit 0
    fi

    if [ "$detach" -eq 0 ] && [ ${#cmd[@]} -eq 0 ] && [ -t 1 ]; then
        clear
    fi

    if [ "$detach" -eq 1 ]; then
        nohup "$PREFIX/bin/proot" "${args[@]}" "${run[@]}" </dev/null >/dev/null 2>&1 &
        echo "Started $LOGIN_ENV in the background (PID $!)"
        exit 0
    fi

    exec "$PREFIX/bin/proot" "${args[@]}" "${run[@]}"
}
