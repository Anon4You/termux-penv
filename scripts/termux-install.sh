#!/data/data/com.termux/files/usr/bin/env bash

# Bootstrap Ver: bootstrap-2025.08.24-r1

red="\e[31m" green="\e[32m" yellow="\e[33m"
blue="\e[34m" cyan="\e[36m" reset="\e[0m\n"

# Variables
base_dir="$PREFIX/var/lib"
program_dir="$base_dir/termux_penv"
. "$(dirname "$0")/env-common.sh"

help_text="termux-penv install termux - Install a Termux chroot on your machine
-----
This program is needed to install Termux chroot from base Termux bootstrap
Chroot installed to $program_dir/termux-<arch>
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

chroot_dir="$program_dir/termux-$arch"

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
Fetching latest Termux Bootstrap for $arch
To: $chroot_dir $reset\n"

case "$(uname -m):$arch" in
    aarch64:aarch64|aarch64:arm|arm*:arm|x86_64:x86_64|x86_64:i686|i686:i686) ;;
    *) printf "$yellow WARNING: $arch environment cannot be logged into on $(uname -m); Termux bootstrap needs its native Android linker. $reset" ;;
esac

# Create temp dir
mkdir -p "$program_dir" || { printf "$red ERROR: Cannot create $program_dir $reset"; exit 1; }
work_dir=$(mktemp -d) || { printf "$red ERROR: Cannot create a temporary directory $reset"; exit 1; }
bootstrap_file="$work_dir/bootstrap.zip"
new_dir=""

# Cleanup function
cleanup() {
    rm -rf "$work_dir" 2>/dev/null
    [ -n "$new_dir" ] && rm -rf "$new_dir" 2>/dev/null
}
trap cleanup EXIT

# Get the latest bootstrap URL from GitHub API
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
    printf "> $green%s$reset\n" " Using custom bootstrap: $bootstrap_url"
else
    printf "> $green Getting latest bootstrap URL...$reset"
    api_url="https://api.github.com/repos/termux/termux-packages/releases"

    # Find the latest bootstrap release
    bootstrap_url=$(curl -s "$api_url" | grep -o "https://.*bootstrap-.*$arch.*\.zip" | head -1)

    if [ -z "$bootstrap_url" ]; then
        # Fallback to manual URL construction if API fails
        printf "> $yellow API failed, using fallback URL...$reset"

        # Get the latest release tag
        latest_tag=$(curl -s "$api_url" | grep -o '"tag_name": "[^"]*"' | head -1 | cut -d'"' -f4)

        if [ -z "$latest_tag" ]; then
            # Ultimate fallback to a known working version
            latest_tag="bootstrap-2025.10.19-r1%2Bapt.android-7"
        fi

        # Construct the URL
        bootstrap_url="https://github.com/termux/termux-packages/releases/download/${latest_tag}/bootstrap-$arch.zip"
    fi
fi

check_bootstrap_arch "$bootstrap_url" "$arch" || exit 1

# Extract bootstrap version from URL for display
bootstrap_ver=$(echo "$bootstrap_url" | grep -o "bootstrap-[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}-r[0-9]" || echo "latest")

printf "> $green Downloading $bootstrap_ver bootstrap...$reset"

# Download file using wget
if ! wget -q --show-progress "$bootstrap_url" -O "$bootstrap_file"; then
    printf "$red ERROR: Failed to download bootstrap.$reset"
    exit 1
fi

# Build the new tree separately so the old chroot stays intact on failure
new_dir=$(mktemp -d "$program_dir/.termux-$arch.new.XXXXXX") || {
    printf "$red ERROR: Cannot create a staging directory in $program_dir $reset"
    exit 1
}
chmod 0755 "$new_dir" || {
    printf "$red ERROR: Cannot set permissions on the staging chroot $reset"
    exit 1
}
mkdir -p "$new_dir/usr" || {
    printf "$red ERROR: Cannot create a staging chroot in $program_dir $reset"
    exit 1
}

# Unpack bootstrap
printf ">$green Unpacking bootstrap to Chroot Dir...$reset"
if ! unzip -q "$bootstrap_file" -d "$new_dir/usr"; then
    printf "$red ERROR: Failed to unzip bootstrap.$reset"
    exit 1
fi

# Create home directory if it doesn't exist
mkdir -p "$new_dir/home" || {
    printf "$red ERROR: Cannot create the staging home directory $reset"
    exit 1
}

# Set up symlinks
printf ">$cyan Setting up symlinks...$reset"
if [ -f "$new_dir/usr/SYMLINKS.txt" ]; then
    while IFS='←' read -r src dest || [ -n "$src" ]; do
        [ -z "$dest" ] && continue
        if ! is_safe_symlink_dest "$dest"; then
            printf "$yellow WARNING: skipping unsafe symlink target '$dest'$reset"
            continue
        fi
        mkdir -p "$(dirname "$new_dir/usr/$dest")"
        if [ -L "$new_dir/usr/$dest" ]; then
            rm -f "$new_dir/usr/$dest"
        fi
        ln -s "$src" "$new_dir/usr/$dest"
    done < "$new_dir/usr/SYMLINKS.txt"
    rm -f "$new_dir/usr/SYMLINKS.txt"
else
    printf "WARNING: SYMLINKS.txt not found.\n"
fi

# Set up permissions
printf ">$yellow Setting up permissions...$reset"
for d in bin libexec lib/apt/apt-helper lib/apt/methods; do
    [ -e "$new_dir/usr/$d" ] && chmod -R 0700 "$new_dir/usr/$d"
done

# Set up additional files
printf ">$blue Setting up additional files...$reset"
mkdir -p "$new_dir/usr/etc"
if [ -f "$new_dir/usr/etc/motd" ]; then
    sed -i "s/Termux!/termux-penv ${arch^^} Container!\nVersion: $bootstrap_ver/" "$new_dir/usr/etc/motd"
    printf "Github: https://github.com/Anon4You/termux-penv\n" >> "$new_dir/usr/etc/motd"
    sed -i "s|at https://termux.dev/issues|To Termux-Penv Github|" "$new_dir/usr/etc/motd"
fi
printf "export BOOTSTRAP_VERSION=\"Latest (%s)\"\n" "$bootstrap_ver" > "$new_dir/usr/etc/termux.penv"

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

printf "$green ✓ Successfully installed latest Termux bootstrap!$reset"
printf "$cyan Use 'termux-penv login termux --arch $arch' to enter the chroot.$reset"
