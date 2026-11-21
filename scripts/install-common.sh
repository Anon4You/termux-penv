#!/data/data/com.termux/files/usr/bin/env bash

# Shared installer for termux and termux-pacman. The wrapper sets ENV_NAME.

red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m'
blue=$'\e[34m' cyan=$'\e[36m' reset=$'\e[0m\n'

base_dir="$PREFIX/var/lib"
program_dir="$base_dir/termux_penv"
. "$(dirname "${BASH_SOURCE[0]}")/env-common.sh"

case "$ENV_NAME" in
    termux)
        env_label="Termux"
        env_prefix="termux"
        repo="termux/termux-packages"
        perms="apt"
        ;;
    termux-pacman)
        env_label="Termux Pacman"
        env_prefix="pacman"
        repo="termux-pacman/termux-packages"
        perms="pacman"
        ;;
    *)
        printf 'ERROR: install-common.sh needs ENV_NAME set to termux or termux-pacman.\n' >&2
        exit 1
        ;;
esac

help_text="termux-penv install $ENV_NAME - Install a $env_label chroot on your machine
-----
This program is needed to install a $env_label chroot from a Termux bootstrap
Chroot installed to $program_dir/$env_prefix-<arch>
-----
Options:
  -h, --help        Show this help
  -r, --reinstall   Remove and reinstall an existing chroot
  --arch ARCH       Bootstrap architecture: aarch64, arm, x86_64 or i686
  --bootstrap URL   Custom HTTPS bootstrap zip or GitHub release tag URL
-----
Default: architecture matching this device"

flag="-i"
arch=""
custom_bootstrap=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            printf '%s\n' "$help_text"
            exit 0
            ;;
        -r|--reinstall)
            flag="-r"
            shift
            ;;
        --arch)
            [ $# -ge 2 ] && [ -n "$2" ] || { printf '%b' "$red ERROR: --arch needs a value $reset"; exit 1; }
            arch="$2"
            shift 2
            ;;
        --arch=*)
            arch="${1#*=}"
            [ -n "$arch" ] || { printf '%b' "$red ERROR: --arch needs a value $reset"; exit 1; }
            shift
            ;;
        --bootstrap|--bootstrap-url)
            [ $# -ge 2 ] && [ -n "$2" ] || { printf '%b' "$red ERROR: --bootstrap needs a URL $reset"; exit 1; }
            custom_bootstrap="$2"
            shift 2
            ;;
        --bootstrap=*|--bootstrap-url=*)
            custom_bootstrap="${1#*=}"
            [ -n "$custom_bootstrap" ] || { printf '%b' "$red ERROR: --bootstrap needs a URL $reset"; exit 1; }
            shift
            ;;
        *)
            printf '%b' "$red ERROR: Unknown argument passed - '$1' $reset"
            printf '%s\n' "$help_text"
            exit 1
            ;;
    esac
done

if [ -z "$arch" ]; then
    arch=$(detect_arch) || {
        printf '%b' "$red ERROR: Unknown architecture: $(uname -m) (use --arch) $reset"
        exit 1
    }
fi
validate_arch "$arch" || {
    printf '%b' "$red ERROR: invalid architecture '$arch' (use aarch64, arm, x86_64 or i686) $reset"
    exit 1
}

if [ -n "$custom_bootstrap" ]; then
    case "$custom_bootstrap" in
        https://*) ;;
        http://*) printf '%b' "$red ERROR: --bootstrap must use https:// $reset"; exit 1 ;;
        *) printf '%b' "$red ERROR: --bootstrap must be an https:// URL $reset"; exit 1 ;;
    esac
fi

command -v realpath >/dev/null 2>&1 || {
    printf '%b' "$red ERROR: realpath not found. Install coreutils with 'pkg install coreutils' $reset"
    exit 1
}
if ! mv --help 2>&1 | grep -q -- '-T'; then
    printf '%b' "$red ERROR: mv does not support -T. Install coreutils with 'pkg install coreutils' $reset"
    exit 1
fi

chroot_dir="$program_dir/$env_prefix-$arch"

reinstall=0
if [ -d "$chroot_dir" ]; then
    if [ "$flag" = "-r" ]; then
        reinstall=1
    else
        printf '%b' "$red ERROR: Chroot dir exists. Use flag -r if you want to reinstall chroot $reset"
        exit 1
    fi
fi

case "$arch" in
    x86_64|i686) printf '%b' "$yellow WARNING: Experimental feature. $reset" ;;
esac

printf '%b' "$blue
Fetching latest $env_label Bootstrap for $arch
To: $chroot_dir $reset"

case "$(uname -m):$arch" in
    aarch64:aarch64|aarch64:arm|arm*:arm|x86_64:x86_64|x86_64:i686|i686:i686) ;;
    *) printf '%b' "$yellow WARNING: $arch environment cannot be logged into on $(uname -m); Termux bootstrap needs its native Android linker. $reset" ;;
esac

mkdir -p "$program_dir" || { printf '%b' "$red ERROR: Cannot create $program_dir $reset"; exit 1; }
work_dir=$(mktemp -d) || { printf '%b' "$red ERROR: Cannot create a temporary directory $reset"; exit 1; }
bootstrap_file="$work_dir/bootstrap.zip"
new_dir=""

cleanup() {
    rm -rf "$work_dir" 2>/dev/null
    [ -n "$new_dir" ] && rm -rf "$new_dir" 2>/dev/null
}
trap cleanup EXIT

if [ -n "$custom_bootstrap" ]; then
    bootstrap_url="$custom_bootstrap"
    if resolved=$(resolve_github_bootstrap "$bootstrap_url" "$arch"); then
        bootstrap_url="$resolved"
    elif [ $? -eq 2 ]; then
        exit 1
    else
        bootstrap_url="${bootstrap_url%/}"
        case "$bootstrap_url" in
            */releases/download/*/) bootstrap_url="${bootstrap_url}bootstrap-$arch.zip" ;;
        esac
    fi
    printf '> %s%s%s' "$green" " Using custom bootstrap: $bootstrap_url" "$reset"
else
    printf '> %s Getting latest bootstrap URL...%s' "$green" "$reset"
    api_url="https://api.github.com/repos/$repo/releases"
    bootstrap_url=$(wget -qO- "$api_url" 2>/dev/null | grep -o "https://.*bootstrap-.*$arch.*\.zip" | head -1)

    if [ -z "$bootstrap_url" ]; then
        printf '> %s API failed, using latest release...%s' "$yellow" "$reset"
        bootstrap_url="https://github.com/$repo/releases/latest/download/bootstrap-$arch.zip"
    fi
fi

check_bootstrap_arch "$bootstrap_url" "$arch" || exit 1

bootstrap_ver=$(printf '%s\n' "$bootstrap_url" | grep -o "bootstrap-[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}-r[0-9]" || echo "latest")
if [ "$perms" = "apt" ]; then
    version_label="Latest ($bootstrap_ver)"
else
    version_label="$bootstrap_ver"
fi

printf '> %s Downloading %s bootstrap...%s' "$green" "$bootstrap_ver" "$reset"

if ! wget -q --show-progress "$bootstrap_url" -O "$bootstrap_file"; then
    printf '%b' "$red ERROR: Failed to download bootstrap.$reset"
    exit 1
fi

new_dir=$(mktemp -d "$program_dir/.$env_prefix-$arch.new.XXXXXX") || {
    printf '%b' "$red ERROR: Cannot create a staging directory in $program_dir $reset"
    exit 1
}
chmod 0755 "$new_dir" || {
    printf '%b' "$red ERROR: Cannot set permissions on the staging chroot $reset"
    exit 1
}
mkdir -p "$new_dir/usr" "$new_dir/home" || {
    printf '%b' "$red ERROR: Cannot create a staging chroot in $program_dir $reset"
    exit 1
}

printf '>%s Unpacking bootstrap to Chroot Dir...%s' "$green" "$reset"
if ! unzip -oq "$bootstrap_file" -d "$new_dir/usr"; then
    printf '%b' "$red ERROR: Failed to unzip bootstrap.$reset"
    exit 1
fi

printf '>%s Setting up symlinks...%s' "$cyan" "$reset"
if [ -L "$new_dir/usr/SYMLINKS.txt" ] ||
    { [ -e "$new_dir/usr/SYMLINKS.txt" ] && [ ! -f "$new_dir/usr/SYMLINKS.txt" ]; }; then
    printf '%b' "$red ERROR: unsafe SYMLINKS.txt in bootstrap.$reset"
    exit 1
elif [ -f "$new_dir/usr/SYMLINKS.txt" ]; then
    root_real=$(realpath -m "$new_dir/usr")
    while IFS='←' read -r src dest || [ -n "$src" ]; do
        [ -z "$dest" ] && continue
        if ! is_safe_symlink_dest "$dest"; then
            printf '%b' "$yellow WARNING: skipping unsafe symlink target '$dest'$reset"
            continue
        fi
        target="$new_dir/usr/$dest"
        parent=$(dirname -- "$target")
        parent_real=$(realpath -m "$parent")
        case "$parent_real/" in
            "$root_real/"*) ;;
            *)
                printf '%b' "$yellow WARNING: skipping symlink outside the chroot: '$dest'$reset"
                continue
                ;;
        esac
        if ! mkdir -p "$parent"; then
            printf '%b' "$yellow WARNING: cannot create symlink parent for '$dest'$reset"
            continue
        fi
        if [ -L "$target" ]; then
            rm -f "$target"
        fi
        ln -s -- "$src" "$target" || printf '%b' "$yellow WARNING: cannot create symlink '$dest'$reset"
    done < "$new_dir/usr/SYMLINKS.txt"
    rm -f "$new_dir/usr/SYMLINKS.txt"
else
    printf 'WARNING: SYMLINKS.txt not found.\n'
fi

printf '>%s Setting up permissions...%s' "$yellow" "$reset"
if [ "$perms" = "apt" ]; then
    for d in bin libexec lib/apt/apt-helper lib/apt/methods; do
        [ -d "$new_dir/usr/$d" ] && [ ! -L "$new_dir/usr/$d" ] && chmod -R 0700 "$new_dir/usr/$d"
    done
else
    for d in bin libexec; do
        [ -d "$new_dir/usr/$d" ] && [ ! -L "$new_dir/usr/$d" ] &&
            find "$new_dir/usr/$d" -type f -exec chmod 0700 {} \; 2>/dev/null
    done
    for d in lib/apt/apt-helper lib/apt/methods; do
        [ -d "$new_dir/usr/$d" ] && [ ! -L "$new_dir/usr/$d" ] && chmod 0700 "$new_dir/usr/$d" 2>/dev/null
    done
fi

printf '>%s Setting up additional files...%s' "$blue" "$reset"
etc_real=$(realpath -m "$new_dir/usr/etc")
root_real=$(realpath -m "$new_dir/usr")
case "$etc_real/" in
    "$root_real/"*) ;;
    *)
        printf '%b' "$red ERROR: archive etc directory points outside the chroot.$reset"
        exit 1
        ;;
esac
mkdir -p "$new_dir/usr/etc" || {
    printf '%b' "$red ERROR: Cannot create $new_dir/usr/etc $reset"
    exit 1
}
if [ -f "$new_dir/usr/etc/motd" ] && [ ! -L "$new_dir/usr/etc/motd" ]; then
    rm -f "$new_dir/usr/etc/motd.orig" "$new_dir/usr/etc/motd.new"
    cp "$new_dir/usr/etc/motd" "$new_dir/usr/etc/motd.orig"
    {
        if [ "$ENV_NAME" = "termux-pacman" ]; then
            echo "Termux-Penv ${arch^^} Container (Pacman)!"
        else
            echo "Termux-Penv ${arch^^} Container!"
        fi
        echo "Version: $bootstrap_ver"
        echo ""
        echo "Termux-Penv on GitHub: https://github.com/Anon4You/termux-penv"
        echo ""
        sed "s|at https://termux.dev/issues|at Termux-Penv GitHub|" "$new_dir/usr/etc/motd.orig"
    } > "$new_dir/usr/etc/motd.new"
    mv -f "$new_dir/usr/etc/motd.new" "$new_dir/usr/etc/motd"
    rm -f "$new_dir/usr/etc/motd.orig"
fi
rm -f "$new_dir/usr/etc/termux.penv"
printf 'export BOOTSTRAP_VERSION="%s"\n' "$version_label" > "$new_dir/usr/etc/termux.penv" || {
    printf '%b' "$red ERROR: Cannot write $new_dir/usr/etc/termux.penv $reset"
    exit 1
}

printf '>%s Cleaning up...%s' "$cyan" "$reset"
find "$new_dir" -name ".DS_Store" -delete 2>/dev/null || true
find "$new_dir" -name "._*" -delete 2>/dev/null || true

if [ "$reinstall" -eq 1 ]; then
    printf '%b' "$yellow > Removing existing chroot... $reset"
    if ! remove_chroot "$chroot_dir"; then
        printf '%b' "$red ERROR: Failed to remove existing chroot at $chroot_dir. New chroot kept at $new_dir.$reset"
        new_dir=""
        exit 1
    fi
fi

if [ -e "$chroot_dir" ] || [ -L "$chroot_dir" ]; then
    printf '%b' "$red ERROR: $chroot_dir already exists. New chroot kept at $new_dir.$reset"
    new_dir=""
    exit 1
fi

if ! mv -T "$new_dir" "$chroot_dir"; then
    printf '%b' "$red ERROR: Failed to move new chroot into place. It was kept at $new_dir.$reset"
    new_dir=""
    exit 1
fi
new_dir=""

printf '%b' "$green ✓ Successfully installed latest $env_label bootstrap!$reset"
printf '%b' "$cyan Use 'termux-penv login $ENV_NAME --arch $arch' to enter the chroot.$reset"
