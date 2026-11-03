#!/data/data/com.termux/files/usr/bin/env bash

# Colors
red="\e[31m" green="\e[32m" yellow="\e[33m"
blue="\e[34m" cyan="\e[36m" reset="\e[0m\n"

# Variables
base_dir="$PREFIX/var/lib"
program_dir="$base_dir/termux_penv"
. "$(dirname "$0")/env-common.sh"

help_text="termux-penv install termux-pacman - Install a Termux Pacman chroot on your machine
-----
This program is needed to install Termux chroot from base Termux bootstrap
Chroot installed to $program_dir/pacman-<arch>
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
            printf "$help_text\n"
            exit 0
            ;;
        -r|--reinstall)
            flag="-r"
            shift
            ;;
        --arch)
            [ $# -ge 2 ] && [ -n "$2" ] || { printf "$red ERROR: --arch needs a value $reset"; exit 1; }
            arch="$2"
            shift 2
            ;;
        --arch=*)
            arch="${1#*=}"
            [ -n "$arch" ] || { printf "$red ERROR: --arch needs a value $reset"; exit 1; }
            shift
            ;;
        --bootstrap|--bootstrap-url)
            [ $# -ge 2 ] && [ -n "$2" ] || { printf "$red ERROR: --bootstrap needs a URL $reset"; exit 1; }
            custom_bootstrap="$2"
            shift 2
            ;;
        --bootstrap=*|--bootstrap-url=*)
            custom_bootstrap="${1#*=}"
            [ -n "$custom_bootstrap" ] || { printf "$red ERROR: --bootstrap needs a URL $reset"; exit 1; }
            shift
            ;;
        *)
            printf "$red ERROR: Unknown argument passed - '$1' $reset"
            printf "$help_text\n"
            exit 1
            ;;
    esac
done

if [ -z "$arch" ]; then
    arch=$(detect_arch) || {
        printf "$red ERROR: Unknown architecture: $(uname -m) (use --arch) $reset"
        exit 1
    }
fi
validate_arch "$arch" || {
    printf "$red ERROR: invalid architecture '$arch' (use aarch64, arm, x86_64 or i686) $reset"
    exit 1
}

if [ -n "$custom_bootstrap" ]; then
    case "$custom_bootstrap" in
        https://*) ;;
        http://*) printf "$red ERROR: --bootstrap must use https:// $reset"; exit 1 ;;
        *) printf "$red ERROR: --bootstrap must be an https:// URL $reset"; exit 1 ;;
    esac
fi

chroot_dir="$program_dir/pacman-$arch"

# Check for existing chroot
reinstall=0
if [ -d "$chroot_dir" ]; then
    if [ "$flag" = "-r" ]; then
        reinstall=1
    else
        printf "$red ERROR: Chroot dir exists. Use flag -r if you want to reinstall chroot $reset"
        exit 1
    fi
fi

case "$arch" in
    x86_64|i686) printf "$yellow WARNING: Experimental feature. $reset" ;;
esac

printf "$blue
Fetching latest Termux Pacman Bootstrap for $arch
To: $chroot_dir $reset"

case "$(uname -m):$arch" in
    aarch64:aarch64|aarch64:arm|arm*:arm|x86_64:x86_64|x86_64:i686|i686:i686) ;;
    *) printf "$yellow WARNING: $arch environment cannot be logged into on $(uname -m); Termux bootstrap needs its native Android linker. $reset" ;;
esac

# Create temp dir
mkdir -p "$program_dir" || { printf "$red ERROR: Cannot create $program_dir $reset"; exit 1; }
work_dir=$(mktemp -d) || { printf "$red ERROR: Cannot create a temporary directory $reset"; exit 1; }
bootstrap_file="$work_dir/bootstrap.zip"
new_dir=""
cleanup() {
    rm -rf "$work_dir" 2>/dev/null
    [ -n "$new_dir" ] && rm -rf "$new_dir" 2>/dev/null
}
trap cleanup EXIT

# Get the latest pacman bootstrap URL
bootstrap_url=""

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
    printf "> $green%s $reset" " Using custom bootstrap: $bootstrap_url"
else
    printf "> $green Getting latest pacman bootstrap URL... $reset"

    # Approach 1: Try GitHub API for termux-pacman releases
    api_url="https://api.github.com/repos/termux-pacman/termux-packages/releases"
    bootstrap_url=$(curl -s "$api_url" | grep -o "https://.*bootstrap-.*$arch.*\.zip" | head -1)

    if [ -z "$bootstrap_url" ]; then
        # Approach 2: Try to get latest release tag and construct URL
        printf "> $yellow API failed, trying to get latest tag... $reset"

        # Get the latest release tag from the releases page
        latest_tag=$(curl -s "$api_url" | grep -o '"tag_name": "[^"]*"' | head -1 | cut -d'"' -f4)

        if [ -n "$latest_tag" ]; then
            # Clean up the tag (remove + signs that might be URL encoded)
            clean_tag=$(echo "$latest_tag" | sed 's/+/%2B/g')
            bootstrap_url="https://github.com/termux-pacman/termux-packages/releases/download/${clean_tag}/bootstrap-$arch.zip"
        fi
    fi

    if [ -z "$bootstrap_url" ]; then
        # Approach 3: Ultimate fallback to a known working version
        printf "> $yellow Using fallback bootstrap URL... $reset"
        bootstrap_url="https://github.com/termux-pacman/termux-packages/releases/download/bootstrap-2025.10.19-r1%2Bpacman-android-7/bootstrap-$arch.zip"
    fi
fi

check_bootstrap_arch "$bootstrap_url" "$arch" || exit 1

# Extract bootstrap version from URL for display
bootstrap_ver=$(echo "$bootstrap_url" | grep -o "bootstrap-[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}-r[0-9]" || echo "latest-pacman")

printf "> $green Downloading $bootstrap_ver bootstrap... $reset"

# Download file using wget
if ! wget -q --show-progress "$bootstrap_url" -O "$bootstrap_file"; then
    printf "$red ERROR: Failed to download bootstrap $reset"
    exit 1
fi

# Build the new tree separately so the old chroot stays intact on failure
new_dir=$(mktemp -d "$program_dir/.pacman-$arch.new.XXXXXX") || {
    printf "$red ERROR: Cannot create a staging directory in $program_dir $reset"
    exit 1
}
chmod 0755 "$new_dir" || {
    printf "$red ERROR: Cannot set permissions on the staging chroot $reset"
    exit 1
}
mkdir -p "$new_dir/usr" "$new_dir/home" || {
    printf "$red ERROR: Cannot create a staging chroot in $program_dir $reset"
    exit 1
}

printf "> $green Unpacking bootstrap to Chroot Dir... $reset"
if ! unzip -q "$bootstrap_file" -d "$new_dir/usr"; then
    printf "$red ERROR: Failed to extract bootstrap $reset"
    exit 1
fi

printf "> $cyan Setting up symlinks... $reset"
if [ -f "$new_dir/usr/SYMLINKS.txt" ]; then
    while IFS='←' read -r src dest || [ -n "$src" ]; do
        [ -z "$dest" ] && continue
        if ! is_safe_symlink_dest "$dest"; then
            printf "$yellow WARNING: skipping unsafe symlink target '$dest' $reset"
            continue
        fi
        mkdir -p "$(dirname "$new_dir/usr/$dest")"
        if [ -L "$new_dir/usr/$dest" ]; then
            rm -f "$new_dir/usr/$dest"
        fi
        ln -s "$src" "$new_dir/usr/$dest" 2>/dev/null || true
    done < "$new_dir/usr/SYMLINKS.txt"

    rm -f "$new_dir/usr/SYMLINKS.txt"
fi

printf "> $yellow Setting up permissions... $reset"
find "$new_dir/usr/bin" -type f -exec chmod 0700 {} \; 2>/dev/null || true
find "$new_dir/usr/libexec" -type f -exec chmod 0700 {} \; 2>/dev/null || true

[ -d "$new_dir/usr/lib/apt/apt-helper" ] && chmod 0700 "$new_dir/usr/lib/apt/apt-helper" 2>/dev/null || true
[ -d "$new_dir/usr/lib/apt/methods" ] && chmod 0700 "$new_dir/usr/lib/apt/methods" 2>/dev/null || true

printf "> $blue Setting up additional files... $reset"
if [ -f "$new_dir/usr/etc/motd" ]; then
    cp "$new_dir/usr/etc/motd" "$new_dir/usr/etc/motd.orig"

    {
        echo "Termux-Penv ${arch^^} Container (Pacman)!"
        echo "Version: $bootstrap_ver"
        echo ""
        echo "Termux-Penv on GitHub: https://github.com/Anon4You/termux-penv"
        echo ""
        cat "$new_dir/usr/etc/motd.orig" | sed "s|at https://termux.dev/issues|at Termux-Penv GitHub|"
    } > "$new_dir/usr/etc/motd.new"

    mv "$new_dir/usr/etc/motd.new" "$new_dir/usr/etc/motd"
    rm -f "$new_dir/usr/etc/motd.orig"
fi

mkdir -p "$new_dir/usr/etc"
echo "export BOOTSTRAP_VERSION=\"$bootstrap_ver\"" > "$new_dir/usr/etc/termux.penv"

printf "> $cyan Cleaning up... $reset"
find "$new_dir" -name ".DS_Store" -delete 2>/dev/null || true
find "$new_dir" -name "._*" -delete 2>/dev/null || true

if [ "$reinstall" -eq 1 ]; then
    printf "$yellow > Removing existing chroot... $reset"
    if ! remove_chroot "$chroot_dir"; then
        printf "$red ERROR: Failed to remove existing chroot at $chroot_dir. New chroot kept at $new_dir.$reset"
        new_dir=""
        exit 1
    fi
fi

if [ -e "$chroot_dir" ] || [ -L "$chroot_dir" ]; then
    printf "$red ERROR: $chroot_dir already exists. New chroot kept at $new_dir.$reset"
    new_dir=""
    exit 1
fi

if ! mv "$new_dir" "$chroot_dir"; then
    printf "$red ERROR: Failed to move new chroot into place. It was kept at $new_dir.$reset"
    new_dir=""
    exit 1
fi
new_dir=""

printf "$green ✓ Successfully installed latest Termux Pacman bootstrap! $reset"
printf "$cyan Use 'termux-penv login termux-pacman --arch $arch' to enter the chroot. $reset"
