#!/data/data/com.termux/files/usr/bin/env bash

# Bootstrap Ver: bootstrap-2025.03.02-r1

# Machine Arch
arch=$(uname -m)

# Bootstrap
bootstrap_ver="bootstrap-2025.04.13-r1 APT"

red="\e[31m" green="\e[32m" yellow="\e[33m"
blue="\e[34m" pink="\e[35m" cyan="\e[36m"
white="\e[37m" black="\e[30m" reset="\e[0m\n"
filred="\e[41;1m" boldw="\e[0;1m"

declare -A bootstrap_sha256=(
    ["aarch64"]="15b294b7dc864a367c45cebe71ca780c58b4f662c8d8d7e3cd66b8f2ffb02fea"
    ["arm"]="367726baf4115c75165da4d8371fbd4e8e8140957026b56a471083d0353dfd5a"
    ["i686"]="fd4d260deaf53714597c42116517654c4dfbacf6f74b19fde4c02225384ed77c"
    ["x86_64"]="9b44b93b6a725efe1cbaf0e88bb9b4672e95c79bf415c1a8523f9135fb30d12d"
)

# Variables
base_dir="$PREFIX/var/lib"
program_dir="$base_dir/termux_penv"
chroot_dir="$program_dir/chroot32"
exec_dir=$(pwd)

help_text="""termux-penv install termux32 - Install 32 bit Termux chroot on your machine
-----
This program is needed to install Termux chroot from base Termux bootstrap located at https://github.com/termux/termux-packages/releases
Bootstrap version: %s
Chroot installed to %s
-----
Standard install of chroot"""

# Check if chroot directory already exists
if [ -d "$chroot_dir" ]; then
    printf "ERROR: Chroot directory already exists. Remove it manually or use a different directory.\n"
    exit 1
fi

# Select arch
if [[ "$arch" == "i686" || "$arch" == "x86_64" || "$arch" == "AMD64" ]]; then
    printf "WARNING: Experimental feature.\n"
    arch="i686"
elif [[ "$arch" == "arm" || "$arch" == "aarch64" || "$arch" == "armv7l" || "$arch" == "armv8l" || "$arch" == "armv7h" || "$arch" == "armv9l" || "$arch" == "armv9h" || "$arch" == "armv9" ]]; then
    arch="arm"
else
    printf "ERROR: Unknown arch\n"
    exit 1
fi


# Use the new URL for arm
bootstrap_url="https://github.com/termux/termux-packages/releases/download/bootstrap-2025.04.13-r1%2Bapt-android-7/bootstrap-$arch.zip"

printf "$blue
Installing Termux Bootstrap $bootstrap_ver for $arch
To: $chroot_dir $reset\n"

# Create temp dir
work_dir=$(mktemp -d)
bootstrap_file="$work_dir/bootstrap.zip"

# Download file using wget
printf "> $green Downloading bootstrap...$reset"
if ! wget -q --show-progress "$bootstrap_url" -O "$bootstrap_file"; then
    printf "$red ERROR: Failed to download bootstrap.$reset"
    exit 1
fi

# Check integrity
printf ">$green Checking integrity...$reset"
expected_sha256="${bootstrap_sha256[$arch]}"
if [ -z "$expected_sha256" ]; then
    printf "$red ERROR: No SHA256 checksum found for architecture $arch.$reset"
    exit 1
fi

computed_sha256=$(sha256sum "$bootstrap_file" | cut -d ' ' -f 1)
if [ "$computed_sha256" != "$expected_sha256" ]; then
    printf "ERROR: SHA256 checksum mismatch.\n"
    printf "Expected: $expected_sha256\n"
    printf "Computed: $computed_sha256\n"
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
printf "Telegram channel: https://t.me/nullxvoid\n" >> "$chroot_dir/usr/etc/motd"
sed -i "s|at https://termux.dev/issues|To Alienkrishn on Telegram|" "$chroot_dir/usr/etc/motd"
printf "export BOOTSTRAP_VERSION=\"$bootstrap_ver\"" > "$chroot_dir/usr/etc/termux.penv"

printf "$cyan Done! Use termux-penv login termux32 to get in chroot.$reset"
