# 🐚 Termux Penv - Termux Chroot Environment Manager 🛠️

**Termux Penv** is a shell script that simplifies the management of **32-bit** and **64-bit** chroot environments in Termux. It allows you to install, log in, and remove chroot environments with ease. 🚀

---

## 🌟 Features

- **Install Chroot Environments**:
  - Install pre-configured 32-bit (`termux32`) or 64-bit (`termux64`) chroot environments. 🏗️
- **Login to Chroot Environments**:
  - Seamlessly log in to your installed chroot environments. 🔑
- **Remove Chroot Environments**:
  - Cleanly remove chroot environments when they are no longer needed. 🗑️
- **Easy to Use**:
  - Simple command-line interface with clear usage instructions. 📜

---

## 🛠️ Installation

You can install **Termux Penv** with a single command:

```bash
curl -sL https://github.com/Anon4You/termux-penv/raw/main/install.sh | bash
```

This will:
1. Download and run the `install.sh` script. 📥
2. Install the `termux-penv` script to `$PREFIX/bin`. 📂
3. Place all required scripts in `$PREFIX/share/termux-penv`. 🗂️

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
- **`termux32`**: 32-bit chroot environment. 🖥️
- **`termux64`**: 64-bit chroot environment. 💻

---

### Examples

1. **Install Termux32**:
   ```bash
   termux-penv install termux32
   ```

2. **Login to Termux64**:
   ```bash
   termux-penv login termux64
   ```

3. **Remove Termux32**:
   ```bash
   termux-penv remove termux32
   ```

4. **Show Help**:
   ```bash
   termux-penv help
   ```

---

## 📂 Scripts

The following scripts are located in `$PREFIX/share/termux-penv`:

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

## 🤝 Contributing

Contributions are welcome! If you have any suggestions, bug reports, or feature requests, please open an issue or submit a pull request. 🛠️

1. **Fork the Repository**. 🍴
2. **Create a New Branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Commit Your Changes**:
   ```bash
   git commit -m "Add your message here"
   ```
4. **Push to the Branch**:
   ```bash
   git push origin feature/your-feature-name
   ```
5. **Open a Pull Request**. 🚀

---

## 📜 License

This project is licensed under the **BSD-3-Clause License**. See the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **Termux**: For providing an amazing terminal emulator and Linux environment for Android. 🐧
- **GitHub Community**: For inspiration and support. 👥

---

## 💖 Support

If you find this project useful, please consider giving it a ⭐️ on GitHub! 🌟

---

Enjoy using **Termux Penv**! If you have any questions, feel free to open an issue or reach out. 😊

---
