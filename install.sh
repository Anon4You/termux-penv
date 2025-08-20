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
PREFIX="/data/data/com.termux/files/usr"
BIN_DIR="$PREFIX/bin"
SHARE_DIR="$PREFIX/share/termux-penv"
REPO_URL="https://github.com/Anon4You/termux-penv/raw/main"

# Check for proot and wget, install if missing
check_dependencies() {
    printf "${BLUE}Checking dependencies...${NC}\n"
    if ! command -v proot &> /dev/null; then
        printf "${RED}proot is not installed. Installing...${NC}\n"
        apt install proot -y
    else
        printf "${GREEN}proot is already installed.${NC}\n"
    fi

    if ! command -v wget &> /dev/null; then
        printf "${RED}wget is not installed. Installing...${NC}\n"
        apt install wget -y
    else
        printf "${GREEN}wget is already installed.${NC}\n"
    fi
}

# Create necessary directories
create_directories() {
    printf "${BLUE}Creating directories...${NC}\n"
    mkdir -p "$SHARE_DIR"
}

# Download and install termux-penv and tp scripts
install_scripts() {
    printf "${BLUE}Downloading scripts...${NC}\n"
    scripts=("termux32.sh" "termux32login.sh" "termux32remove.sh" "termux64.sh" "termux64login.sh" "termux64remove.sh")
    for script in "${scripts[@]}"; do
        printf "${CYAN}Downloading $script...${NC}\n"
        wget -q "$REPO_URL/scripts/$script" -O "$SHARE_DIR/$script"
        chmod +x "$SHARE_DIR/$script"
    done

    printf "${CYAN}Downloading termux-penv...${NC}\n"
    wget -q "$REPO_URL/bin/termux-penv" -O "$BIN_DIR/termux-penv"
    chmod +x "$BIN_DIR/termux-penv"

    printf "${CYAN}Downloading tp...${NC}\n"
    wget -q "$REPO_URL/bin/tp" -O "$BIN_DIR/tp"
    chmod +x "$BIN_DIR/tp"
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