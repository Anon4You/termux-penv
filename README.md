# 🐚 Termux Penv - Termux Chroot Environment Manager 🛠️

**Termux Penv** is a powerful shell script that simplifies the management of **32-bit** and **64-bit** chroot environments in Termux. It's specifically designed to help developers with **cross-compilation** and running applications built for different architectures. 🚀

---

## 🌟 Features

- **Multi-Architecture Support**:
  - Install and run both 32-bit (`termux32`) and 64-bit (`termux64`) Termux environments side-by-side. 🏗️
- **Cross-Compilation Ready**:
  - Perfect for compiling applications for different CPU architectures. 🔧
- **Development Environment**:
  - Test your applications on different architectures without needing multiple devices. 🧪
- **Easy Management**:
  - Install, log in, and remove chroot environments with simple commands. 📜
- **Isolated Environments**:
  - Keep your development environments separate and clean. 🧹

---

## 🛠️ Installation

### Method 1: Quick Install (Recommended)
```bash
curl -sL https://github.com/Anon4You/termux-penv/raw/main/install.sh | bash
```

This will:
1. Download and run the `install.sh` script. 📥
2. Install the `termux-penv` script to `$PREFIX/bin`. 📂
3. Place all required scripts in `$PREFIX/share/termux-penv`. 🗂️

### Method 2: Install from Termux Void Repository
**Ensure you have the [Termux Void Repository](https://github.com/termuxvoid) added to your Termux.**

```bash
apt install termux-penv -y
```

---

## 🚀 Usage

### General Syntax
```bash
termux-penv [command] [environment]
```

### Commands
- **`install` or `i`**: Install a chroot environment. 🏗️
- **`login` or `l`**: Log in to a chroot environment. 🔑
- **`remove` or `r`**: Remove a chroot environment. 🗑️
- **`help` or `h`**: Show usage instructions. 📜

### Environments
- **`termux32`**: 32-bit chroot environment (ideal for ARMv7, i686). 🖥️
- **`termux64`**: 64-bit chroot environment (for aarch64, x86_64). 💻

---

## 🎯 Cross-Compilation Examples

### 1. Install Both Environments
```bash
# Install 64-bit environment (matches your host architecture)
termux-penv install termux64

# Install 32-bit environment (for cross-compilation)
termux-penv install termux32
```

### 2. Cross-Compile from 64-bit to 32-bit
```bash
# Login to your 64-bit environment
termux-penv login termux64

# Install cross-compilation tools
apt install clang gcc make binutils

# Compile for 32-bit ARM from your 64-bit environment
CC="clang -target armv7a-linux-androideabi" ./configure --host=arm-linux-androideabi
make
```

### 3. Test in Target Environment
```bash
# Test your 32-bit compiled binary in the 32-bit environment
termux-penv login termux32
./your-compiled-32bit-binary
```

### 4. Development Workflow
```bash
# Develop in 64-bit environment
termux-penv login termux64
# Write and test code

# Cross-compile for 32-bit
make clean
CC="clang -target armv7a-linux-androideabi" make

# Test in 32-bit environment
termux-penv login termux32
./your-app-32bit
```

---

## 📂 Scripts Location

All scripts are located in `$PREFIX/share/termux-penv`:

- **Installation Scripts**:
  - `termux32.sh`: Installs the 32-bit chroot environment. 🏗️
  - `termux64.sh`: Installs the 64-bit chroot environment. 🏗️

- **Login Scripts**:
  - `termux32login.sh`: Logs in to the 32-bit chroot environment. 🔑
  - `termux64login.sh`: Logs in to the 64-bit chroot environment. 🔑

- **Removal Scripts**:
  - `termux32remove.sh`: Removes the 32-bit chroot environment. 🗑️
  - `termux64remove.sh`: Removes the 64-bit chroot environment. 🗑️

---

## 🎪 Use Cases

1. **Game Development**: Test games on different architectures. 🎮
2. **Library Development**: Ensure compatibility across architectures. 📚
3. **System Programming**: Develop low-level system tools. ⚙️
4. **Education**: Learn about different CPU architectures. 🎓
5. **Security Research**: Analyze malware for different platforms. 🔍

---

## 🤝 Contributing

We welcome contributions! If you have suggestions, bug reports, or feature requests:

1. **Fork the Repository**. 🍴
2. **Create a Feature Branch**:
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. **Commit Your Changes**:
   ```bash
   git commit -m "Add amazing feature"
   ```
4. **Push to the Branch**:
   ```bash
   git push origin feature/amazing-feature
   ```
5. **Open a Pull Request**. 🚀

---

## 📜 License

BSD-3-Clause License. See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- **Termux Team**: For the amazing Android terminal environment. 🐧
- **Cross-Compilation Community**: For tools and knowledge sharing. 👥
- **Open Source Contributors**: Making development accessible to all. 🌍

---

## 💖 Support

If this tool helps your development workflow, please give it a ⭐️ on GitHub! 🌟

---

**Happy Cross-Compiling!** Enjoy building applications for multiple architectures with Termux Penv! 🎉