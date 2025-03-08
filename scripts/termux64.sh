#!/data/data/com.termux/files/usr/bin/env bash

# Bootstrap Ver: bootstrap-2025.03.02-r1

# Machine Arch
arch=$(uname -m)

# Bootstrap
bootstrap_ver="bootstrap-2025.03.02-r1 APT"

red="\e[31m" green="\e[32m" yellow="\e[33m"
blue="\e[34m" pink="\e[35m" cyan="\e[36m"
white="\e[37m" black="\e[30m" reset="\e[0m\n"
filred="\e[41;1m" boldw="\e[0;1m"


declare -A bootstrap_sha256=(
    ["aarch64"]="cc8ba6b951f1a009381183dde78979c0578d6824d5b87b1cb7f5cf9dbd8fa1cf"
    ["arm"]="f2143dfd3e68df0503a46ad0348dd64f7f228cbda97729d7fdf40df288679d46"
    ["i686"]="cd4899a78720800ecab87389ca7279afc5dc46c79ba13ff7c92ca6b4c04950a2"
    ["x86_64"]="d83ec84103322717a2a2434ea51d0077b9f4e23f6ca1a02ac5252f88bfc451a5"
)

# Variables
base_dir="$PREFIX/var/lib"
program_dir="$base_dir/termux_penv"
chroot_dir="$program_dir/chroot64"
exec_dir=$(pwd)

help_text="""termux-penv install termux64 - Install 64 bit Termux chroot on your machine
-----
This program is needed to install Termux chroot from base Termux bootstrap located at https://github.com/termux/termux-packages/releases
Bootstrap version: %s
Chroot installed to %s
-----
Flags:
    -h  Show help
    -f  Force install up on existing chroot
    -r  Reinstall chroot | REMOVES ALL DATA!
    -i  Standard install of chroot"""

# Check up args.
if [ $# -gt 0 ]; then
    flag=$1
else
    flag="-i"
fi

if [ "$flag" == "-h" ]; then
    printf "$help_text\n $bootstrap_ver $chroot_dir"
    exit 0
fi

if [[ "$flag" != "-i" && "$flag" != "-r" && "$flag" != "-f" ]]; then
    printf "ERROR: Unknown argument passed - '$flag'"
    printf "$help_text\n" "$bootstrap_ver" "$chroot_dir"
    exit 1
fi

# All checks
if [[ "$flag" != "-f" && "$flag" != "-r" && -d "$chroot_dir" ]]; then
    printf "ERROR: Chroot dir exists. Use flag -r if you want to reinstall chroot or use termux-remove64 to remove it"
    exit 1
elif [[ "$flag" == "-r" && -d "$chroot_dir" ]]; then
    printf "> Removing existing chroot directory..."
    rm -rf "$chroot_dir"
fi

# Select arch
if [[ "$arch" == "i686" || "$arch" == "x86_64" || "$arch" == "AMD64" ]]; then
    printf "WARNING: Experimental feature."
    arch="x86_64"
elif [[ "$arch" == "arm" || "$arch" == "aarch64" || "$arch" == "armv7l" || "$arch" == "armv8l" || "$arch" == "armv7h" || "$arch" == "armv9l" || "$arch" == "armv9h" || "$arch" == "armv9" ]]; then
    arch="aarch64"
else
    printf "ERROR: Unknown arch"
    exit 1
fi

# Use the new URL for arm
bootstrap_url="https://github.com/termux/termux-packages/releases/download/bootstrap-2025.03.02-r1%2Bapt-android-7/bootstrap-$arch.zip"

printf "$blue
Installing Termux Bootstrap $bootstrap_ver for $arch
To: $chroot_dir $reset\n"

# Create temp dir
work_dir=$(mktemp -d)
bootstrap_file="$work_dir/bootstrap.zip"

# Download file using wget
printf ">$green Downloading bootstrap...$reset"
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
    printf "ERROR: SHA256 checksum mismatch."
    printf "Expected: $expected_sha256"
    printf "Computed: $computed_sha256"
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
    printf "WARNING: SYMLINKS.txt not found."
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

printf "$cyan Done! Use termux-penv login termux64 to get in chroot.$reset"
