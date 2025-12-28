#!/data/data/com.termux/files/usr/bin/env bash

# Colors
red="\e[31m" green="\e[32m" yellow="\e[33m"
blue="\e[34m" pink="\e[35m" cyan="\e[36m"
white="\e[37m" black="\e[30m" reset="\e[0m\n"
filred="\e[41;1m" boldw="\e[0;1m"

# Variables
base_dir="$PREFIX/var/lib"
program_dir="$base_dir/termux_penv"
chroot_dir="$program_dir/pacman-chroot64"
exec_dir=$(pwd)
tmp_dir="${TMPDIR:-/tmp}"

help_text="termux-penv install termux-pacman64 - Install 64 bit Termux chroot on your machine
-----
This program is needed to install Termux chroot from base Termux bootstrap
Chroot installed to %s
-----
Standard install of chroot"

# Check arguments
if [ $# -gt 0 ]; then
    flag="$1"
else
    flag="-i"
fi

if [ "$flag" = "-h" ]; then
    printf "$help_text\n" "$chroot_dir"
    exit 0
fi

if [ "$flag" != "-i" ] && [ "$flag" != "-r" ] && [ "$flag" != "-f" ]; then
    printf "$red ERROR: Unknown argument passed - '$flag' $reset"
    printf "$help_text\n" "$chroot_dir"
    exit 1
fi

# Check for existing chroot
if [ "$flag" != "-f" ] && [ "$flag" != "-r" ] && [ -d "$chroot_dir" ]; then
    printf "$red ERROR: Chroot dir exists. Use flag -r if you want to reinstall chroot $reset"
    exit 1
fi

if [ "$flag" = "-r" ] && [ -d "$chroot_dir" ]; then
    printf "$yellow > Removing existing chroot... $reset"
    rm -rf "$chroot_dir"
fi

# Detect architecture
arch=$(uname -m)

# Updated architecture selection logic
if [[ "$arch" == "i686" || "$arch" == "x86_64" || "$arch" == "AMD64" ]]; then
    printf "$yellow WARNING: Experimental feature. $reset"
    arch="x86_64"
elif [[ "$arch" == "arm" || "$arch" == "aarch64" || "$arch" == "armv7l" || "$arch" == "armv8l" ]]; then
    arch="aarch64"
else
    printf "$red ERROR: Unknown architecture: $arch $reset"
    exit 1
fi

printf "$blue
Fetching latest Termux Pacman Bootstrap for $arch
To: $chroot_dir $reset"

# Create directories
mkdir -p "$chroot_dir/usr" "$chroot_dir/home"

# Get the latest pacman bootstrap URL
printf "> $green Getting latest pacman bootstrap URL... $reset"

# Try multiple approaches to get the latest bootstrap URL
bootstrap_url=""

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

# Extract bootstrap version from URL for display
bootstrap_ver=$(echo "$bootstrap_url" | grep -o "bootstrap-[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}-r[0-9]" || echo "latest-pacman")

printf "> $green Downloading $bootstrap_ver bootstrap... $reset"

# Download file using wget
if ! wget -q --show-progress "$bootstrap_url" -O "$tmp_dir/bootstrap.zip"; then
    printf "$red ERROR: Failed to download bootstrap $reset"
    exit 1
fi

printf "> $green Unpacking bootstrap to Chroot Dir... $reset"
if ! unzip -q "$tmp_dir/bootstrap.zip" -d "$chroot_dir/usr"; then
    printf "$red ERROR: Failed to extract bootstrap $reset"
    rm -f "$tmp_dir/bootstrap.zip"
    exit 1
fi

# Clean up
rm -f "$tmp_dir/bootstrap.zip"

printf "> $cyan Setting up symlinks... $reset"
# Process SYMLINKS file
if [ -f "$chroot_dir/usr/SYMLINKS.txt" ]; then
    # Use proper unicode character for the delimiter (← = U+2190)
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -n "$line" ]; then
            # Extract source and target using awk with proper unicode delimiter
            source_file=$(echo "$line" | awk -F '←' '{print $1}')
            target_link=$(echo "$line" | awk -F '←' '{print $2}')
            
            # Skip if target link is empty or problematic
            if [ -z "$target_link" ] || [ "$target_link" = "." ] || [ "$target_link" = ".." ]; then
                continue
            fi
            
            # Create target directory if it doesn't exist
            target_dir=$(dirname "$chroot_dir/usr/$target_link")
            mkdir -p "$target_dir"
            
            # Remove existing symlink if it exists
            if [ -L "$chroot_dir/usr/$target_link" ]; then
                rm -f "$chroot_dir/usr/$target_link"
            fi
            
            # Create the symlink
            if [ -n "$source_file" ] && [ -n "$target_link" ]; then
                ln -s "$source_file" "$chroot_dir/usr/$target_link" 2>/dev/null || true
            fi
        fi
    done < "$chroot_dir/usr/SYMLINKS.txt"
    
    # Remove SYMLINKS file
    rm -f "$chroot_dir/usr/SYMLINKS.txt"
fi

printf "> $yellow Setting up permissions... $reset"
# Set executable permissions safely
find "$chroot_dir/usr/bin" -type f -exec chmod 0700 {} \; 2>/dev/null || true
find "$chroot_dir/usr/libexec" -type f -exec chmod 0700 {} \; 2>/dev/null || true

# Set permissions on specific apt directories if they exist
[ -d "$chroot_dir/usr/lib/apt/apt-helper" ] && chmod 0700 "$chroot_dir/usr/lib/apt/apt-helper" 2>/dev/null || true
[ -d "$chroot_dir/usr/lib/apt/methods" ] && chmod 0700 "$chroot_dir/usr/lib/apt/methods" 2>/dev/null || true

printf "> $blue Setting up additional files... $reset"
# Create motd file if it exists
if [ -f "$chroot_dir/usr/etc/motd" ]; then
    # Backup original motd
    cp "$chroot_dir/usr/etc/motd" "$chroot_dir/usr/etc/motd.orig"
    
    # Create new motd
    {
        echo "Termux-Penv ${arch^^} Container (Pacman)!"
        echo "Version: $bootstrap_ver"
        echo ""
        echo "Termux-Penv on GitHub: https://github.com/Anon4You/termux-penv"
        echo ""
        cat "$chroot_dir/usr/etc/motd.orig" | sed "s|at https://termux.dev/issues|at Termux-Penv GitHub|"
    } > "$chroot_dir/usr/etc/motd.new"
    
    mv "$chroot_dir/usr/etc/motd.new" "$chroot_dir/usr/etc/motd"
    rm -f "$chroot_dir/usr/etc/motd.orig"
fi

# Create version file
mkdir -p "$chroot_dir/usr/etc"
echo "export BOOTSTRAP_VERSION=\"$bootstrap_ver\"" > "$chroot_dir/usr/etc/termux.penv"

printf "> $cyan Cleaning up... $reset"
# Remove any problematic files that might cause issues
find "$chroot_dir" -name ".DS_Store" -delete 2>/dev/null || true
find "$chroot_dir" -name "._*" -delete 2>/dev/null || true

printf "$green ✓ Successfully installed latest Termux Pacman bootstrap! $reset"
printf "$cyan Use 'termux-penv login termux-pacman64' to enter the chroot. $reset"
