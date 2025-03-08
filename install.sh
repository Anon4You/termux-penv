#!/data/data/com.termux/files/usr/bin/env bash

# Termux Penv Installer
# Installs the termux-penv script and required files.

# Define directories
PREFIX="/data/data/com.termux/files/usr"
BIN_DIR="$PREFIX/bin"
SHARE_DIR="$PREFIX/share/termux-penv"
REPO_URL="https://github.com/Anon4You/termux-penv/raw/main"

# Check for proot and wget, install if missing
check_dependencies() {
    echo "🔍 Checking dependencies..."
    if ! command -v proot &> /dev/null; then
        echo "❌ proot is not installed. Installing..."
        apt install proot -y
    else
        echo "✅ proot is already installed."
    fi

    if ! command -v wget &> /dev/null; then
        echo "❌ wget is not installed. Installing..."
        apt install wget -y
    else
        echo "✅ wget is already installed."
    fi
}

# Create necessary directories
create_directories() {
    echo "📂 Creating directories..."
    mkdir -p "$SHARE_DIR"
}

# Download and install termux-penv and tp scripts
install_scripts() {
    echo "📥 Downloading scripts..."
    scripts=("termux32.sh" "termux32login.sh" "termux32remove.sh" "termux64.sh" "termux64login.sh" "termux64remove.sh")
    for script in "${scripts[@]}"; do
        echo "⬇️ Downloading $script..."
        wget -q "$REPO_URL/scripts/$script" -O "$SHARE_DIR/$script"
        chmod +x "$SHARE_DIR/$script"
    done

    echo "⬇️ Downloading termux-penv..."
    wget -q "$REPO_URL/bin/termux-penv" -O "$BIN_DIR/termux-penv"
    chmod +x "$BIN_DIR/termux-penv"

    echo "⬇️ Downloading tp..."
    wget -q "$REPO_URL/bin/tp" -O "$BIN_DIR/tp"
    chmod +x "$BIN_DIR/tp"
}

# Main function
main() {
    echo "🚀 Starting Termux Penv installation..."
    check_dependencies
    create_directories
    install_scripts
    echo "🎉 Installation complete! Run 'termux-penv help' for usage instructions."
}

# Run the script
main