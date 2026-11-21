#!/data/data/com.termux/files/usr/bin/env bash

# Termux Penv Installer
# Installs the termux-penv script and required files.

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define directories
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN_DIR="$PREFIX/bin"
SHARE_DIR="$PREFIX/share/termux-penv"
REPO_URL="https://github.com/Anon4You/termux-penv/raw/main"

# Check for required commands, install if missing
check_dependencies() {
    printf "${BLUE}Checking dependencies...${NC}\n"
    for dep in proot wget unzip; do
        if ! command -v "$dep" &> /dev/null; then
            printf "${RED}$dep is not installed. Installing...${NC}\n"
            if ! apt install "$dep" -y; then
                printf "${RED}Failed to install $dep.${NC}\n"
                exit 1
            fi
        else
            printf "${GREEN}$dep is already installed.${NC}\n"
        fi
    done
}

# Create necessary directories
create_directories() {
    printf "${BLUE}Creating directories...${NC}\n"
    mkdir -p "$SHARE_DIR"
}

# Download everything first, then move it into place.
install_scripts() {
    printf "${BLUE}Downloading scripts...${NC}\n"
    scripts=("env-common.sh" "install-common.sh" "login-common.sh" "termux-install.sh" "termux-pacman-install.sh" "termux-login.sh" "termux-pacman-login.sh")
    tmp=$(mktemp -d) || {
        printf "${RED}Failed to create a temporary directory.${NC}\n"
        exit 1
    }
    trap 'rm -rf "$tmp"' EXIT

    for script in "${scripts[@]}"; do
        printf "${CYAN}Downloading $script...${NC}\n"
        if ! wget -q "$REPO_URL/scripts/$script" -O "$tmp/$script"; then
            printf "${RED}Failed to download $script.${NC}\n"
            exit 1
        fi
    done

    printf "${CYAN}Downloading termux-penv...${NC}\n"
    if ! wget -q "$REPO_URL/bin/termux-penv" -O "$tmp/termux-penv"; then
        printf "${RED}Failed to download termux-penv.${NC}\n"
        exit 1
    fi
    chmod +x "$tmp"/*

    for script in "${scripts[@]}"; do
        mv -f "$tmp/$script" "$SHARE_DIR/$script"
    done
    mv -f "$tmp/termux-penv" "$BIN_DIR/termux-penv"

    printf "${CYAN}Creating tp symlink...${NC}\n"
    ln -sf termux-penv "$BIN_DIR/tp"

    rm -rf "$tmp"
    trap - EXIT
}

# Main function
main() {
    printf "${YELLOW}Starting Termux Penv installation...${NC}\n"
    check_dependencies
    create_directories
    install_scripts
    printf "${GREEN}Installation complete! Run 'termux-penv help' for usage instructions.${NC}\n"
}

# Run the script
main
