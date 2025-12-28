#!/data/data/com.termux/files/usr/bin/env bash

# Bootstrap Ver: bootstrap-2025.08.24-r1

# Machine Arch
arch=$(uname -m)

red="\e[31m" green="\e[32m" yellow="\e[33m"
blue="\e[34m" pink="\e[35m" cyan="\e[36m"
white="\e[37m" black="\e[30m" reset="\e[0m\n"
filred="\e[41;1m" boldw="\e[0;1m"

# Variables
base_dir="$PREFIX/var/lib"
program_dir="$base_dir/termux_penv"
chroot_dir="$program_dir/chroot64"
exec_dir=$(pwd)

# Check if chroot directory already exists
if [ -d "$chroot_dir" ]; then
    printf "ERROR: Chroot directory already exists. Remove it manually or use a different directory.\n"
    exit 1
fi

# Select arch
if [[ "$arch" == "i686" || "$arch" == "x86_64" || "$arch" == "AMD64" ]]; then
    printf "WARNING: Experimental feature.\n"
    arch="x86_64"
elif [[ "$arch" == "arm" || "$arch" == "aarch64" || "$arch" == "armv7l" || "$arch" == "armv8l" ]]; then
    arch="aarch64"
else
    printf "ERROR: Unknown arch: $arch\n"
    exit 1
fi

printf "$blue
Fetching latest Termux Bootstrap for $arch
To: $chroot_dir $reset\n"

# Create temp dir
work_dir=$(mktemp -d)
bootstrap_file="$work_dir/bootstrap.zip"

# Cleanup function
cleanup() {
    rm -rf "$work_dir" 2>/dev/null
}
trap cleanup EXIT

# Get the latest bootstrap URL from GitHub API
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

# Extract bootstrap version from URL for display
bootstrap_ver=$(echo "$bootstrap_url" | grep -o "bootstrap-[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}-r[0-9]" || echo "latest")

printf "> $green Downloading $bootstrap_ver bootstrap...$reset"

# Download file using wget
if ! wget -q --show-progress "$bootstrap_url" -O "$bootstrap_file"; then
    printf "$red ERROR: Failed to download bootstrap.$reset"
    exit 1
fi

# Unpack bootstrap
printf ">$green Unpacking bootstrap to Chroot Dir...$reset"
mkdir -p "$chroot_dir/usr"
if ! unzip -q "$bootstrap_file" -d "$chroot_dir/usr"; then
    printf "$red ERROR: Failed to unzip bootstrap.$reset"
    exit 1
fi

# Create home directory if it doesn't exist
if [ ! -d "$chroot_dir/home" ]; then
    mkdir -p "$chroot_dir/home"
fi

# Set up symlinks
printf ">$cyan Setting up symlinks...$reset"
if [ -f "$chroot_dir/usr/SYMLINKS.txt" ]; then
    while IFS='←' read -r src dest; do
        if [ -L "$chroot_dir/usr/$dest" ]; then
            rm "$chroot_dir/usr/$dest"
        fi
        ln -s "$src" "$chroot_dir/usr/$dest"
    done < "$chroot_dir/usr/SYMLINKS.txt"
else
    printf "WARNING: SYMLINKS.txt not found.\n"
fi

# Set up permissions
printf ">$yellow Setting up permissions...$reset"
chmod -R 0700 "$chroot_dir/usr/bin" "$chroot_dir/usr/libexec" "$chroot_dir/usr/lib/apt/apt-helper" "$chroot_dir/usr/lib/apt/methods"

# Set up additional files
printf ">$blue Setting up additional files...$reset"
sed -i "s/Termux!/termux-penv ${arch^^} Container!\nVersion: $bootstrap_ver/" "$chroot_dir/usr/etc/motd"
printf "Github: https://github.com/Anon4You/termux-penv\n" >> "$chroot_dir/usr/etc/motd"
sed -i "s|at https://termux.dev/issues|To Termux-Penv Github|" "$chroot_dir/usr/etc/motd"
printf "export BOOTSTRAP_VERSION=\"Latest ($bootstrap_ver)\"" > "$chroot_dir/usr/etc/termux.penv"

printf "$green ✓ Successfully installed latest Termux bootstrap!$reset"
printf "$cyan Use 'termux-penv login termux64' to enter the chroot.$reset"

