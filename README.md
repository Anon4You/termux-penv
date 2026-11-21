# Termux Penv v3.1.0 - Chroot Environment Manager 🛠️

**Termux Penv** is a sleek shell script for managing native Termux chroot environments in Termux. Install a Termux (APT) or Termux Pacman environment for a supported architecture, side by side, for 32-bit/64-bit testing. 🚀

---

## Features 🌟

- **Any Supported Architecture**: Install `aarch64`, `arm`, `x86_64` or `i686` environments with `--arch` when this device can run them natively. 🖥️
- **Multi-Architecture**: Keep 64-bit and 32-bit environments of the same CPU family side by side. 🖥️
- **Auto Detection**: `termux-penv install termux` picks the architecture of this device. 🔍
- **Isolated Testing**: Test apps in clean Termux environments for the architectures this device can run. 🧪
- **Pacman Support**: Use `termux-pacman` for Arch-style package management. 📦
- **Simple Commands**: Install, login, run, and remove environments with ease. 📜

## Why termux-penv instead of proot-distro? 🤔

[proot-distro](https://github.com/termux/proot-distro) installs full Linux distributions (Alpine, Arch, Debian, Ubuntu, ...) from Docker/registry images and is the right tool for a general-purpose Linux container. It also offers Termux images.

termux-penv is narrower: it installs the real **Termux bootstrap** (APT or Pacman) for a chosen architecture. That is what makes it useful for native work on one device:

- Keep aarch64 (64-bit) and arm/armv7a (32-bit) Termux environments side by side where the kernel supports 32-bit binaries.
- Build and test 32-bit binaries next to your normal 64-bit Termux, using Termux paths, packages and toolchains instead of a generic distro.
- Install independent environments per architecture with one tool; each architecture gets its own directory.
- Get a chroot that behaves like Termux, not like Ubuntu or Alpine.

Use proot-distro when you need a full distro or cross-architecture emulation. Use termux-penv when the point is a native Termux environment.

## Architecture limits ⚠️

Termux bootstrap binaries are Android/bionic binaries. Their ELF interpreter is the device's `/system/bin/linker64` (or `/system/bin/linker`), not a loader included in the bootstrap. A QEMU user-mode emulator cannot replace that with a loader for another architecture, so cross-architecture Termux login is not supported.

| Host (`uname -m`) | aarch64 guest | arm guest | x86_64 guest | i686 guest |
| --- | --- | --- | --- | --- |
| aarch64 | native | native* | unsupported | unsupported |
| armv7l / armv8l | unsupported | native | unsupported | unsupported |
| x86_64 | unsupported | unsupported | native | native* |
| i686 / i386 | unsupported | unsupported | unsupported | native |

`*` Requires 32-bit compatibility in the kernel. Some 64-bit-only Android kernels/devices cannot run 32-bit binaries at all.

- A 64-bit chroot on a 32-bit device is unsupported.
- Different CPU families are unsupported, even with QEMU user packages installed.
- `termux-penv` rejects an unsupported architecture before starting proot. `--qemu` and `--emulator` do not make Termux cross-architecture work; they are diagnostic options for native environments.
- Use [proot-distro](https://github.com/termux/proot-distro) for cross-architecture Linux distributions that include their own dynamic loader.
- Environments created by version 2.x used different names (`termux32`, `termux64`, `termux-pacman32`, `termux-pacman64`); `remove` recognizes these legacy names, or reinstall them with the new `termux` / `termux-pacman` names.

---

## Installation 📥

### Option 1: Quick Install (Recommended)
```bash
curl -sL https://github.com/Anon4You/termux-penv/raw/main/install.sh | bash
```

Installs `termux-penv` to `$PREFIX/bin` and scripts to `$PREFIX/share/termux-penv`.

### Option 2: Termux Void Repository
Add the [Termux Void Repository](https://github.com/termuxvoid), then:
```bash
apt install termux-penv -y
```

---

## Usage 🚀

### Syntax
```bash
termux-penv [command] [environment] [options] [command...]
```

### Commands
- `install` (`i`): Set up a chroot environment. 🏗️
- `login` (`l`): Access a chroot environment. 🔑
- `run`: Run one command in a chroot without a banner. 🏃
- `remove` (`r`): Delete a chroot environment. 🗑️
- `help` (`h`): Show usage information. 📖

### Options
Run `termux-penv login --help` for the full login and run option list (proot-distro style), including `--arch`, `--isolated`, `--shared-home`, `--shared-tmp`, `--bind`, `--work-dir`, `--env`, `--detach` and more.

By default the chroot uses its own private home directory (`$PREFIX/var/lib/termux_penv/<type>-<arch>/home`) instead of the Termux home. The host `/data` tree is not bound; only the Android runtime paths Termux binaries need (`/system`, `/apex`, `/vendor`, `/linkerconfig`) are shared. Use `--shared-home` to share the Termux home, like `proot-distro`.

`--isolated` drops shared storage and legacy host paths, while keeping the Android runtime paths. `--minimal` is isolated mode without System V IPC. `--detach` starts a command in the background, so it requires a command.

```bash
termux-penv login termux --shared-home
termux-penv login termux --isolated --bind /sdcard:/sdcard
termux-penv login termux -d -- sleep 60
termux-penv run termux -w /home -- ls -la
```

### Run one command
`run` executes one command without the login banner or an interactive shell. It accepts the same options as `login`, but requires a command. The default working directory is `/home`; `-w` must be an absolute path inside the chroot:

```bash
termux-penv run termux uname -m
termux-penv run termux --arch arm -- id
termux-penv run termux -w /tmp -- ls -la
```

### Install a different architecture
By default `install` picks the architecture matching the device. Use `--arch` to choose another native or 32-bit-compatible architecture:

- `aarch64`: 64-bit ARM
- `arm`: 32-bit ARM (armv7a)
- `x86_64`: 64-bit x86
- `i686`: 32-bit x86

```bash
termux-penv install termux
termux-penv install termux --arch arm
termux-penv install termux-pacman --arch arm
```

Every architecture is a separate environment, so native 64-bit and 32-bit environments can coexist:

```bash
termux-penv login termux --arch aarch64
termux-penv login termux --arch arm
termux-penv remove termux --arch arm
```

Without `--arch`, `login` uses this device's architecture when it is installed, otherwise the only installed architecture. Login rejects an architecture the device cannot run natively; it never uses QEMU for the Termux bootstrap.

To replace an existing architecture (for example to refresh the bootstrap), reinstall it:

```bash
termux-penv install termux --arch aarch64 -r
```

`remove` also deletes version 2.x legacy directories for the selected environment and architecture.

On a device that cannot run the chosen architecture natively, login stops with an error instead of starting proot (see Architecture limits above).

### Custom bootstrap
Use `--bootstrap` to install from a specific GitHub release tag or a direct zip archive:

```bash
termux-penv install termux --bootstrap https://github.com/termux/termux-packages/releases/tag/bootstrap-2026.11.01-r1%2Bapt.android-7
termux-penv install termux-pacman --arch arm --bootstrap https://mirror.example/bootstrap-arm.zip
```

A release tag URL is looked up through the GitHub API to find the matching `bootstrap-<arch>.zip` asset; if the API is unavailable, the canonical `<repo>/releases/download/<tag>/bootstrap-<arch>.zip` URL is used. A direct zip URL is used as-is. Custom URLs must use HTTPS, and a URL whose filename clearly names another architecture is rejected. `--bootstrap-url` is an alias.

### Environments
- `termux`: Termux environment with APT. 🖥️
- `termux-pacman`: Termux environment with Pacman. 📦

---

## Examples 🎯

### 1. Install Environments
```bash
termux-penv install termux
termux-penv install termux --arch arm
termux-penv install termux-pacman
termux-penv install termux-pacman --arch arm
```

### 2. Cross-Compile (64-bit to 32-bit)
```bash
termux-penv install termux --arch arm
termux-penv login termux --arch arm
apt install clang gcc make binutils
CC="clang -target armv7a-linux-androideabi" ./configure --host=arm-linux-androideabi
make
```

### 3. Test Application
```bash
termux-penv login termux --arch arm
./your-compiled-32bit-binary
```
Or in a Pacman environment:
```bash
termux-penv login termux-pacman --arch arm
./your-compiled-32bit-binary
```

---

## Script Locations 📂

Scripts are stored in `$PREFIX/share/termux-penv`:
- **Install**: `termux-install.sh`, `termux-pacman-install.sh`
- **Login**: `termux-login.sh`, `termux-pacman-login.sh`, `login-common.sh`
- **Shared**: `env-common.sh` (architecture detection and resolution), `install-common.sh` (installer used by both environments)
- **Remove**: handled by `termux-penv` itself

---

## Use Cases 🎮

- Cross-compile games, libraries, or system tools to 32-bit ARM. ⚙️
- Test apps across native 32-bit and 64-bit environments. 🧪
- Develop with Pacman-based package management. 📦
- Inspect how packages behave in a clean Termux environment. 🔍

---

## Contributing 🤝

1. Fork the repository. 🍴
2. Create a branch: `git checkout -b feature/new-feature`
3. Commit changes: `git commit -m "Add new feature"`
4. Push: `git push origin feature/new-feature`
5. Submit a pull request. 🚀

Run `bash tests/run.sh` from the repository root. It uses temporary fake commands and does not touch installed environments.

Report bugs or suggest features via GitHub Issues.

---

## License 📜

BSD-3-Clause License. See [LICENSE](LICENSE) for details.

---

## Acknowledgments 🙏

- **Termux Team**: For the awesome Termux platform. 🐧
- **Termux-Pacman Team**: For enabling Pacman-based environments. 📦
- **Open Source Community**: For shared tools and knowledge. 🌍

---

## Support 💖

Star the project on GitHub if it boosts your workflow! 🌟

---

**Version 3.1.0** - private chroot home, corrected isolated/minimal bindings, hardened installers, legacy v2 removal, and a 147-check test suite

