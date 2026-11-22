#!/data/data/com.termux/files/usr/bin/bash

# Small regression suite for termux-penv. Uses fake proot/wget/unzip.

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

real_prefix="${PREFIX:-/data/data/com.termux/files/usr}"
PREFIX="$tmp/prefix"
HOME="$tmp/home"
program_dir="$PREFIX/var/lib/termux_penv"
share="$PREFIX/share/termux-penv"

checks=0
failures=0

pass() { checks=$((checks + 1)); }
fail() {
    checks=$((checks + 1))
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$*" >&2
}

assert_eq() {
    if [ "$1" = "$2" ]; then
        pass
    else
        fail "$3 (expected '$1', got '$2')"
    fi
}

assert_ne() {
    if [ "$1" != "$2" ]; then
        pass
    else
        fail "$3 (unexpected '$1')"
    fi
}

assert_contains() {
    if grep -Fq -- "$1" "$2"; then
        pass
    else
        fail "$3 (missing '$1' in $2)"
    fi
}

assert_not_contains() {
    if grep -Fq -- "$1" "$2"; then
        fail "$3 (unexpected '$1' in $2)"
    else
        pass
    fi
}

assert_file() {
    if [ -f "$1" ]; then
        pass
    else
        fail "$2 (missing file $1)"
    fi
}

assert_no_dir() {
    if [ ! -e "$1" ]; then
        pass
    else
        fail "$2 (unexpected $1)"
    fi
}

mkdir -p "$PREFIX/bin" "$PREFIX/share/termux-penv" "$program_dir" "$HOME"
cp "$root/scripts/"*.sh "$share/"
cp "$root/bin/termux-penv" "$PREFIX/bin/"
chmod +x "$PREFIX/bin/termux-penv" "$share/"*.sh

. "$share/env-common.sh"
host=$(detect_arch) || {
    printf 'Unsupported host architecture: %s\n' "$(uname -m)" >&2
    exit 1
}

mkdir -p "$program_dir/termux-$host/usr" "$program_dir/termux-$host/home"

cat > "$PREFIX/bin/proot" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
: "${PROOT_LOG:?}"
for arg in "$@"; do
    printf 'arg=%s\n' "$arg" >> "$PROOT_LOG"
done
printf 'LD_PRELOAD=%s\n' "${LD_PRELOAD-<unset>}" >> "$PROOT_LOG"
EOF
chmod +x "$PREFIX/bin/proot"

# Helpers
is_safe_symlink_dest 'usr/bin' && pass || fail 'safe symlink path rejected'
is_safe_symlink_dest '../etc/passwd' && fail 'unsafe ../ symlink accepted' || pass
is_safe_symlink_dest '/etc/passwd' && fail 'absolute symlink accepted' || pass
is_safe_symlink_dest 'a/../b' && fail 'embedded .. symlink accepted' || pass
is_safe_symlink_dest '.' && fail 'dot symlink accepted' || pass
is_safe_symlink_dest '' && fail 'empty symlink accepted' || pass

mkdir -p "$tmp/rmtarget"
printf 'keep\n' > "$tmp/rmtarget/file"
ln -s "$tmp/rmtarget" "$tmp/rmlink"
remove_chroot "$tmp/rmlink" && pass || fail 'symlinked chroot not removed'
assert_file "$tmp/rmtarget/file" 'remove_chroot followed a symlink'
if [ ! -L "$tmp/rmlink" ]; then pass; else fail 'remove_chroot left the symlink'; fi
remove_chroot '' && fail 'remove_chroot accepted empty path' || pass
remove_chroot / && fail 'remove_chroot accepted /' || pass
remove_chroot . && fail 'remove_chroot accepted .' || pass
remove_chroot .. && fail 'remove_chroot accepted ..' || pass

check_bootstrap_arch 'https://example/bootstrap-aarch64.zip' aarch64 2>/dev/null && pass ||
    fail 'matching bootstrap arch rejected'
check_bootstrap_arch 'https://example/bootstrap-x86_64.zip' aarch64 2>"$tmp/arch.err" &&
    fail 'mismatched bootstrap arch accepted' || pass
assert_contains 'bootstrap URL is for x86_64, not aarch64' "$tmp/arch.err" 'mismatch error'
check_bootstrap_arch 'https://example/my-bootstrap.zip' aarch64 2>"$tmp/arch.err" && pass ||
    fail 'unnamed bootstrap rejected'
assert_contains 'cannot determine bootstrap architecture' "$tmp/arch.err" 'unnamed warning'

# Resolver: no matching asset must be a hard failure, not a 404 fallback.
wget() {
    printf '%s\n' '{"assets":[{"browser_download_url":"https://example/bootstrap-x86_64.zip"}]}'
}
resolved=$(resolve_github_bootstrap 'https://github.com/o/r/releases/tag/t' aarch64 2>"$tmp/resolve.err")
rc=$?
unset -f wget
assert_eq 2 "$rc" 'no-asset resolver status'
assert_eq '' "$resolved" 'no-asset resolver output'
assert_contains 'has no bootstrap for aarch64' "$tmp/resolve.err" 'no-asset error'
assert_contains 'bootstrap-x86_64.zip' "$tmp/resolve.err" 'available assets'

wget() {
    printf '%s\n' '{"assets":[{"browser_download_url":"https://example/bootstrap-aarch64.zip"}]}'
}
resolved=$(resolve_github_bootstrap 'https://github.com/o/r/releases/tag/t' aarch64 2>/dev/null)
rc=$?
unset -f wget
assert_eq 0 "$rc" 'matching asset status'
assert_eq 'https://example/bootstrap-aarch64.zip' "$resolved" 'matching asset URL'
resolve_github_bootstrap 'https://example/bootstrap.zip' aarch64 >/dev/null 2>&1
assert_eq 1 "$?" 'direct zip status'
wget() { return 1; }
resolved=$(resolve_github_bootstrap 'https://github.com/o/r/releases/tag/t+1' aarch64 2>/dev/null)
rc=$?
unset -f wget
assert_eq 0 "$rc" 'API failure status'
assert_eq 'https://github.com/o/r/releases/download/t%2B1/bootstrap-aarch64.zip' "$resolved" \
    'canonical fallback URL'

# Login: command arguments must stay separate; LD_PRELOAD must be removed.
proot_log="$tmp/proot.log"
: > "$proot_log"
PROOT_LOG="$proot_log" "$share/termux-login.sh" --arch "$host" -- echo 'a b' >"$tmp/out" 2>"$tmp/err"
assert_eq 0 "$?" 'command login exit'
assert_contains 'arg=echo' "$proot_log" 'command name kept'
assert_contains 'arg=a b' "$proot_log" 'command argument kept'
if grep -Fq 'arg=sh' "$proot_log"; then fail 'command was passed through sh -c'; else pass; fi

# apt writes its archive cache under /data/data/com.termux/cache.
if [ -d "$program_dir/termux-$host/data/data/com.termux/cache/apt/archives/partial" ]; then
    pass
else
    fail 'login did not create the apt cache directory'
fi

# run: execute one command without the login banner.
: > "$proot_log"
PROOT_LOG="$proot_log" "$PREFIX/bin/termux-penv" run termux --arch "$host" echo 'a b' >"$tmp/out" 2>"$tmp/err"
assert_eq 0 "$?" 'run command exit'
assert_contains 'arg=echo' "$proot_log" 'run command name kept'
assert_contains 'arg=a b' "$proot_log" 'run command argument kept'
if grep -Fq 'Logging into' "$tmp/err"; then fail 'run printed the login banner'; else pass; fi

"$PREFIX/bin/termux-penv" run termux --arch "$host" >"$tmp/out" 2>"$tmp/err"
assert_ne 0 "$?" 'run without command accepted'
assert_contains 'run needs a command' "$tmp/err" 'run missing command error'

"$PREFIX/bin/termux-penv" run --help >"$tmp/out" 2>&1
assert_eq 0 "$?" 'run --help failed'
assert_contains 'Usage: termux-penv run' "$tmp/out" 'run help usage'

"$share/termux-login.sh" --arch "$host" --user root -- true >"$tmp/out" 2>&1
assert_ne 0 "$?" '--user accepted'
assert_contains "Unknown option '--user'" "$tmp/out" '--user error'

"$share/termux-login.sh" --arch "$host" --hostname test -- true >"$tmp/out" 2>&1
assert_ne 0 "$?" '--hostname accepted'
assert_contains "Unknown option '--hostname'" "$tmp/out" '--hostname error'

preload="$real_prefix/lib/libtermux-exec.so"
if [ -f "$preload" ]; then
    : > "$proot_log"
    LD_PRELOAD="$preload" PROOT_LOG="$proot_log" \
        "$share/termux-login.sh" --arch "$host" -- true >/dev/null 2>"$tmp/err"
    assert_eq 0 "$?" 'preload login exit'
    assert_contains 'LD_PRELOAD=<unset>' "$proot_log" 'LD_PRELOAD removed'
else
    printf 'SKIP: no %s for LD_PRELOAD check\n' "$preload"
fi

"$share/termux-login.sh" --arch "$host" --get-proot-cmd --env FOO=bar >"$tmp/getcmd" 2>"$tmp/err"
assert_eq 0 "$?" 'get-proot-cmd exit'
assert_contains 'env -u LD_PRELOAD HOME=/home' "$tmp/getcmd" 'get-proot-cmd environment'
assert_contains 'FOO=bar' "$tmp/getcmd" 'get-proot-cmd custom env'
assert_contains "$PREFIX/bin/proot" "$tmp/getcmd" 'get-proot-cmd proot path'

# Bind set: Android runtime paths stay; the host /data tree is never exposed.
"$share/termux-login.sh" --arch "$host" --get-proot-cmd >"$tmp/getcmd" 2>"$tmp/err"
assert_contains '/system:/system' "$tmp/getcmd" 'default system bind'
assert_contains '--sysvipc' "$tmp/getcmd" 'default sysvipc'
assert_not_contains '/data:/data' "$tmp/getcmd" 'host /data bind'
if [ -d /storage ]; then
    assert_contains '/storage:/storage' "$tmp/getcmd" 'default storage bind'
fi

"$share/termux-login.sh" --arch "$host" --isolated --get-proot-cmd >"$tmp/getcmd" 2>"$tmp/err"
assert_contains '/system:/system' "$tmp/getcmd" 'isolated system bind'
assert_not_contains '/storage:/storage' "$tmp/getcmd" 'isolated storage bind'
assert_not_contains '/data:/data' "$tmp/getcmd" 'isolated /data bind'

"$share/termux-login.sh" --arch "$host" --minimal --get-proot-cmd >"$tmp/getcmd" 2>"$tmp/err"
assert_contains '/system:/system' "$tmp/getcmd" 'minimal system bind'
assert_not_contains '--sysvipc' "$tmp/getcmd" 'minimal sysvipc'
"$share/termux-login.sh" --arch "$host" --minimal --kernel test-kernel --get-proot-cmd >"$tmp/getcmd" 2>"$tmp/err"
assert_contains '-k test-kernel' "$tmp/getcmd" 'minimal explicit kernel'

mkdir -p "$tmp/tmpdir/.X11-unix"
TMPDIR="$tmp/tmpdir" "$share/termux-login.sh" --arch "$host" --shared-home --shared-tmp --shared-x11 --get-proot-cmd >"$tmp/getcmd" 2>"$tmp/err"
assert_contains "$tmp/home:/home" "$tmp/getcmd" 'shared home bind'
assert_contains "$tmp/tmpdir:/tmp" "$tmp/getcmd" 'shared tmp bind'
assert_contains "$tmp/tmpdir/.X11-unix:/tmp/.X11-unix" "$tmp/getcmd" 'shared X11 bind'
"$share/termux-login.sh" --arch "$host" --bind /sdcard:/sdcard --get-proot-cmd >"$tmp/getcmd" 2>"$tmp/err"
assert_contains '/sdcard:/sdcard' "$tmp/getcmd" 'custom bind'

"$share/termux-login.sh" --arch "$host" --bind= -- true >"$tmp/out" 2>"$tmp/err"
assert_ne 0 "$?" 'empty --bind accepted'
assert_contains '--bind needs SRC:DEST' "$tmp/err" 'empty --bind error'

"$share/termux-login.sh" --arch "$host" --emulator= -- true >"$tmp/out" 2>"$tmp/err"
assert_ne 0 "$?" 'empty --emulator accepted'
assert_contains '--emulator needs a file' "$tmp/err" 'empty --emulator error'

"$share/termux-login.sh" --arch "$host" --env BAD >"$tmp/out" 2>"$tmp/err"
assert_ne 0 "$?" 'invalid --env accepted'
assert_contains 'expects VAR=VALUE' "$tmp/err" 'invalid --env error'

"$share/termux-login.sh" --arch "$host" --work-dir relative >"$tmp/out" 2>"$tmp/err"
assert_ne 0 "$?" 'relative --work-dir accepted'
assert_contains 'must be an absolute path' "$tmp/err" 'relative --work-dir error'

"$share/termux-login.sh" --arch "$host" --get-proot-cmd -- echo hi >"$tmp/getcmd" 2>"$tmp/err"
assert_contains '--cwd=/home' "$tmp/getcmd" 'command default cwd'
"$share/termux-login.sh" --arch "$host" --work-dir /tmp --get-proot-cmd -- true >"$tmp/getcmd" 2>"$tmp/err"
assert_contains '--cwd=/tmp' "$tmp/getcmd" 'explicit work dir'

"$share/termux-login.sh" --arch "$host" --detach >"$tmp/out" 2>"$tmp/err"
assert_ne 0 "$?" 'detach without command accepted'
assert_contains '--detach needs a command' "$tmp/err" 'detach without command error'

: > "$proot_log"
PROOT_LOG="$proot_log" "$share/termux-login.sh" --arch "$host" -d -- echo hi >"$tmp/out" 2>"$tmp/err"
assert_eq 0 "$?" 'detach with command failed'
assert_contains 'Started termux in the background' "$tmp/out" 'detach message'
for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -Fq 'arg=echo' "$proot_log" && break
    sleep 0.1
done
assert_contains 'arg=echo' "$proot_log" 'detached command did not run'

# A symlinked usr/bin must not be bound; proot would follow it on the host.
case "$host" in
    aarch64) sym_arch=arm ;;
    x86_64) sym_arch=i686 ;;
    *) sym_arch="" ;;
esac
if [ -n "$sym_arch" ]; then
    mkdir -p "$program_dir/termux-$sym_arch/usr" "$tmp/hostbin"
    ln -s "$tmp/hostbin" "$program_dir/termux-$sym_arch/usr/bin"
    "$share/termux-login.sh" --arch "$sym_arch" --get-proot-cmd >"$tmp/getcmd" 2>"$tmp/err"
    assert_eq 0 "$?" 'symlinked bin login failed'
    assert_not_contains "$program_dir/termux-$sym_arch/usr/bin:/bin" "$tmp/getcmd" 'symlinked bin bind'
    rm -rf "$program_dir/termux-$sym_arch"
fi

"$share/termux-login.sh" --arch "$host" --qemu=1 >"$tmp/out" 2>"$tmp/err"
assert_ne 0 "$?" '--qemu=1 accepted'
assert_contains "Unknown option '--qemu=1'" "$tmp/err" '--qemu=1 error'

"$share/termux-login.sh" --arch= >"$tmp/out" 2>"$tmp/err"
assert_ne 0 "$?" 'empty login --arch accepted'
assert_contains 'needs a value' "$tmp/err" 'empty login --arch error'

# Login: Termux bootstraps cannot run on another CPU family, even with QEMU.
case "$host" in
    aarch64) cross=x86_64 ;;
    x86_64) cross=aarch64 ;;
    arm*) cross=aarch64 ;;
    i686) cross=x86_64 ;;
    *) cross="" ;;
esac
if [ -n "$cross" ]; then
    mkdir -p "$program_dir/termux-$cross/usr"
    "$share/termux-login.sh" --arch "$cross" -- true >"$tmp/out" 2>"$tmp/err"
    assert_ne 0 "$?" 'cross-arch login accepted'
    assert_contains 'cannot run on this' "$tmp/err" 'cross-arch error'
    assert_contains 'QEMU cannot supply' "$tmp/err" 'cross-arch linker error'
    rm -rf "$program_dir/termux-$cross"
fi

# Main remove: empty --arch must not silently remove the host environment.
printf 'keep\n' > "$program_dir/termux-$host/usr/marker"
"$PREFIX/bin/termux-penv" remove termux --arch= >"$tmp/out" 2>&1
assert_ne 0 "$?" 'empty remove --arch accepted'
assert_file "$program_dir/termux-$host/usr/marker" 'empty remove --arch deleted env'

# Main remove: a failed rm must be reported.
mkdir -p "$program_dir/termux-arm/usr"
printf 'keep\n' > "$program_dir/termux-arm/usr/marker"
mkdir -p "$tmp/failrm"
printf '#!/data/data/com.termux/files/usr/bin/bash\nexit 1\n' > "$tmp/failrm/rm"
chmod +x "$tmp/failrm/rm"
PATH="$tmp/failrm:$PATH" "$PREFIX/bin/termux-penv" remove termux --arch arm >"$tmp/out" 2>&1
assert_ne 0 "$?" 'failed rm reported success'
assert_file "$program_dir/termux-arm/usr/marker" 'failed rm deleted env'
assert_contains 'Failed to remove' "$tmp/out" 'failed rm error'

# Installers: empty values and plain HTTP must fail before any download.
for args in '--arch=' '--bootstrap=' '--bootstrap http://example/bootstrap.zip'; do
    bash "$share/termux-install.sh" $args >"$tmp/out" 2>&1
    assert_ne 0 "$?" "apt installer accepted $args"
    bash "$share/termux-pacman-install.sh" $args >"$tmp/out" 2>&1
    assert_ne 0 "$?" "pacman installer accepted $args"
done

# A tag with no matching asset must fail instead of trying a 404 fallback.
mkdir -p "$tmp/nomatch"
cat > "$tmp/nomatch/wget" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
printf '%s\n' '{"assets":[{"browser_download_url":"https://example/bootstrap-x86_64.zip"}]}'
EOF
chmod +x "$tmp/nomatch/wget"
PATH="$tmp/nomatch:$PATH" bash "$share/termux-install.sh" --arch i686 \
    --bootstrap 'https://github.com/o/r/releases/tag/t' >"$tmp/out" 2>&1
assert_ne 0 "$?" 'installer accepted no matching asset'
assert_contains 'has no bootstrap for i686' "$tmp/out" 'installer no-asset error'
assert_no_dir "$program_dir/termux-i686" 'installer created chroot after no asset'

# Fake wget/unzip for successful and failed install tests.
mkdir -p "$tmp/fakebin"
cat > "$tmp/fakebin/wget" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
out=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-O" ]; then
        shift
        out="$1"
    fi
    shift
done
[ -n "$out" ] || exit 1
printf 'fake zip\n' > "$out"
EOF
cat > "$tmp/fakebin/unzip" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
dest=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
        shift
        dest="$1"
    fi
    shift
done
[ -n "$dest" ] || exit 1
mkdir -p "$dest/etc"
printf 'Welcome to Termux!\n' > "$dest/etc/motd"
EOF
chmod +x "$tmp/fakebin/wget" "$tmp/fakebin/unzip"

# A GitHub tag URL must resolve to the matching release asset.
mkdir -p "$tmp/tagbin"
cat > "$tmp/tagbin/wget" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
printf '%s\n' "$*" >> "$WGET_LOG"
case "$*" in
    *api.github.com*)
        printf '%s\n' '{"assets":[{"browser_download_url":"https://example/bootstrap-x86_64.zip"}]}'
        exit 0
        ;;
esac
out=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-O" ]; then
        shift
        out="$1"
    fi
    shift
done
[ -n "$out" ] || exit 1
printf 'fake zip\n' > "$out"
EOF
chmod +x "$tmp/tagbin/wget"
: > "$tmp/tag.log"
WGET_LOG="$tmp/tag.log" PATH="$tmp/tagbin:$tmp/fakebin:$PATH" \
    bash "$share/termux-install.sh" --arch x86_64 -r \
    --bootstrap 'https://github.com/o/r/releases/tag/t' >"$tmp/out" 2>&1
assert_eq 0 "$?" 'tag install failed'
assert_contains 'https://example/bootstrap-x86_64.zip' "$tmp/tag.log" 'tag asset used'

PATH="$tmp/fakebin:$PATH" bash "$share/termux-install.sh" --arch i686 \
    --bootstrap 'https://example/bootstrap-i686.zip' >"$tmp/out" 2>&1
assert_eq 0 "$?" 'apt install failed'
assert_file "$program_dir/termux-i686/usr/etc/termux.penv" 'apt install missing termux.penv'

"$PREFIX/bin/termux-penv" remove termux --arch i686 >"$tmp/out" 2>&1
assert_eq 0 "$?" 'remove failed'
assert_no_dir "$program_dir/termux-i686" 'remove left environment behind'

PATH="$tmp/fakebin:$PATH" bash "$share/termux-pacman-install.sh" --arch arm \
    --bootstrap 'https://example/bootstrap-arm.zip' >"$tmp/out" 2>&1
assert_eq 0 "$?" 'pacman install failed'
assert_file "$program_dir/pacman-arm/usr/etc/termux.penv" 'pacman install missing termux.penv'

# An API failure must use the latest release URL, not a stale hardcoded tag.
mkdir -p "$tmp/fallbackbin"
cat > "$tmp/fallbackbin/wget" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
printf '%s\n' "$*" >> "$WGET_LOG"
out=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-O" ]; then
        shift
        out="$1"
    fi
    shift
done
if [ -n "$out" ]; then
    printf 'fake zip\n' > "$out"
fi
exit 0
EOF
chmod +x "$tmp/fallbackbin/wget"
: > "$tmp/fallback.log"
WGET_LOG="$tmp/fallback.log" PATH="$tmp/fallbackbin:$tmp/fakebin:$PATH" \
    bash "$share/termux-pacman-install.sh" --arch arm -r >"$tmp/out" 2>&1
assert_eq 0 "$?" 'pacman fallback install failed'
assert_contains 'releases/latest/download/bootstrap-arm.zip' "$tmp/fallback.log" 'pacman fallback URL'
assert_not_contains 'bootstrap-2025.10.19' "$tmp/fallback.log" 'stale pacman fallback URL'

# Unsafe SYMLINKS.txt targets must be skipped.
mkdir -p "$tmp/malbin"
cat > "$tmp/malbin/unzip" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
dest=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
        shift
        dest="$1"
    fi
    shift
done
[ -n "$dest" ] || exit 1
mkdir -p "$dest"
printf '%s\n' '../../outside←../../escape' > "$dest/SYMLINKS.txt"
EOF
chmod +x "$tmp/malbin/unzip"
PATH="$tmp/malbin:$tmp/fakebin:$PATH" bash "$share/termux-install.sh" --arch x86_64 -r \
    --bootstrap 'https://example/bootstrap-x86_64.zip' >"$tmp/out" 2>&1
assert_eq 0 "$?" 'symlink install failed'
if [ ! -e "$program_dir/escape" ] && [ ! -L "$program_dir/escape" ]; then
    pass
else
    fail 'unsafe symlink escaped the chroot'
fi

# A symlinked SYMLINKS.txt must abort before the old chroot is removed.
mkdir -p "$tmp/symlinkfilebin"
cat > "$tmp/symlinkfilebin/unzip" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
dest=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
        shift
        dest="$1"
    fi
    shift
done
[ -n "$dest" ] || exit 1
mkdir -p "$dest"
ln -s /etc/hostname "$dest/SYMLINKS.txt"
EOF
chmod +x "$tmp/symlinkfilebin/unzip"
printf 'keep\n' > "$program_dir/termux-x86_64/usr/marker"
PATH="$tmp/symlinkfilebin:$tmp/fakebin:$PATH" bash "$share/termux-install.sh" --arch x86_64 -r \
    --bootstrap 'https://example/bootstrap-x86_64.zip' >"$tmp/out" 2>&1
assert_ne 0 "$?" 'symlinked SYMLINKS.txt accepted'
assert_contains 'unsafe SYMLINKS.txt' "$tmp/out" 'symlinked SYMLINKS.txt error'
assert_file "$program_dir/termux-x86_64/usr/marker" 'unsafe SYMLINKS.txt removed old chroot'

# A symlinked parent must not let SYMLINKS.txt write outside the chroot.
mkdir -p "$tmp/parentbin"
cat > "$tmp/parentbin/unzip" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
dest=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
        shift
        dest="$1"
    fi
    shift
done
[ -n "$dest" ] || exit 1
mkdir -p "$dest"
ln -s "$OUTSIDE" "$dest/link"
printf '%s\n' 'x←link/evil' > "$dest/SYMLINKS.txt"
EOF
chmod +x "$tmp/parentbin/unzip"
rm -rf "$tmp/outside"
OUTSIDE="$tmp/outside" PATH="$tmp/parentbin:$tmp/fakebin:$PATH" \
    bash "$share/termux-install.sh" --arch x86_64 -r \
    --bootstrap 'https://example/bootstrap-x86_64.zip' >"$tmp/out" 2>&1
assert_eq 0 "$?" 'symlink parent install failed'
if [ ! -e "$tmp/outside" ]; then
    pass
else
    fail 'symlinked parent escaped the chroot'
fi

# chmod must not follow an archive symlink at the top of a permission path.
mkdir -p "$tmp/chmodbin" "$tmp/chmodtarget"
printf 'x\n' > "$tmp/chmodtarget/file"
chmod 0755 "$tmp/chmodtarget/file"
cat > "$tmp/chmodbin/unzip" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
dest=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
        shift
        dest="$1"
    fi
    shift
done
[ -n "$dest" ] || exit 1
mkdir -p "$dest"
ln -s "$CHMOD_TARGET" "$dest/bin"
EOF
chmod +x "$tmp/chmodbin/unzip"
CHMOD_TARGET="$tmp/chmodtarget" PATH="$tmp/chmodbin:$tmp/fakebin:$PATH" \
    bash "$share/termux-install.sh" --arch x86_64 -r \
    --bootstrap 'https://example/bootstrap-x86_64.zip' >"$tmp/out" 2>&1
assert_eq 0 "$?" 'symlinked chmod install failed'
assert_eq 755 "$(stat -c %a "$tmp/chmodtarget/file")" 'chmod followed archive symlink'

# Archive symlinks for installer-written files must be replaced, not followed.
mkdir -p "$tmp/writebin"
cat > "$tmp/writebin/unzip" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
dest=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
        shift
        dest="$1"
    fi
    shift
done
[ -n "$dest" ] || exit 1
mkdir -p "$dest/etc"
printf 'Welcome to Termux!\n' > "$dest/etc/motd"
ln -s "$OUTSIDE/termux.penv" "$dest/etc/termux.penv"
ln -s "$OUTSIDE/motd.orig" "$dest/etc/motd.orig"
ln -s "$OUTSIDE/motd.new" "$dest/etc/motd.new"
EOF
chmod +x "$tmp/writebin/unzip"
rm -rf "$tmp/writeoutside"
mkdir -p "$tmp/writeoutside"
OUTSIDE="$tmp/writeoutside" PATH="$tmp/writebin:$tmp/fakebin:$PATH" \
    bash "$share/termux-install.sh" --arch x86_64 -r \
    --bootstrap 'https://example/bootstrap-x86_64.zip' >"$tmp/out" 2>&1
assert_eq 0 "$?" 'write-through install failed'
assert_eq '' "$(ls -A "$tmp/writeoutside")" 'archive symlink wrote outside the chroot'
assert_file "$program_dir/termux-x86_64/usr/etc/termux.penv" 'write-through missing termux.penv'
if [ ! -L "$program_dir/termux-x86_64/usr/etc/termux.penv" ]; then
    pass
else
    fail 'termux.penv is still a symlink'
fi

# An archive symlink named etc must not redirect installer writes outside.
mkdir -p "$tmp/etcbin" "$tmp/etctarget"
cat > "$tmp/etcbin/unzip" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
dest=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
        shift
        dest="$1"
    fi
    shift
done
[ -n "$dest" ] || exit 1
mkdir -p "$dest"
ln -s "$ETC_TARGET" "$dest/etc"
EOF
chmod +x "$tmp/etcbin/unzip"
ETC_TARGET="$tmp/etctarget" PATH="$tmp/etcbin:$tmp/fakebin:$PATH" \
    bash "$share/termux-install.sh" --arch x86_64 -r \
    --bootstrap 'https://example/bootstrap-x86_64.zip' >"$tmp/out" 2>&1
assert_ne 0 "$?" 'unsafe etc symlink accepted'
assert_eq '' "$(ls -A "$tmp/etctarget")" 'etc symlink wrote outside the chroot'

# Unknown arguments must be printed literally, not used as a printf format.
bash "$share/termux-install.sh" '%s%s' >"$tmp/out" 2>&1
assert_ne 0 "$?" 'format string argument accepted'
assert_contains '%s%s' "$tmp/out" 'format string argument mangled'

# A direct zip naming another architecture must be rejected before old removal.
printf 'keep\n' > "$program_dir/termux-x86_64/usr/marker"
PATH="$tmp/fakebin:$PATH" bash "$share/termux-install.sh" --arch x86_64 -r \
    --bootstrap 'https://example/bootstrap-aarch64.zip' >"$tmp/out" 2>&1
assert_ne 0 "$?" 'mismatched direct zip accepted'
assert_contains 'for aarch64, not x86_64' "$tmp/out" 'mismatched direct zip error'
assert_file "$program_dir/termux-x86_64/usr/marker" 'mismatched direct zip removed old chroot'

# A failed unzip must leave the old chroot untouched.
mkdir -p "$tmp/failbin"
printf '#!/data/data/com.termux/files/usr/bin/bash\nexit 1\n' > "$tmp/failbin/unzip"
chmod +x "$tmp/failbin/unzip"
printf 'keep\n' > "$program_dir/termux-$host/usr/marker"
PATH="$tmp/failbin:$tmp/fakebin:$PATH" bash "$share/termux-install.sh" --arch "$host" -r \
    --bootstrap "https://example/bootstrap-$host.zip" >"$tmp/out" 2>&1
assert_ne 0 "$?" 'failed unzip reported success'
assert_file "$program_dir/termux-$host/usr/marker" 'failed unzip deleted old chroot'
if compgen -G "$program_dir/.termux-$host.new.*" >/dev/null; then
    fail 'failed unzip left staging directory'
else
    pass
fi

# install.sh must download everything before replacing installed files.
mkdir -p "$tmp/installbin"
cat > "$tmp/installbin/wget" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
out=""
url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -O) shift; out="$1" ;;
        https://*) url="$1" ;;
    esac
    shift
done
[ -n "$out" ] || exit 1
[ -n "$url" ] || exit 1
[ "$FAIL_SCRIPT" = "${url##*/}" ] && exit 1
case "$url" in
    */scripts/*) src="$REPO_ROOT/scripts/${url##*/}" ;;
    */bin/termux-penv) src="$REPO_ROOT/bin/termux-penv" ;;
    *) exit 1 ;;
esac
[ -f "$src" ] || exit 1
cp "$src" "$out"
EOF
chmod +x "$tmp/installbin/wget"

iprefix="$tmp/iprefix"
mkdir -p "$iprefix/bin" "$iprefix/share/termux-penv"
printf 'old\n' > "$iprefix/share/termux-penv/env-common.sh"
REPO_ROOT="$root" FAIL_SCRIPT=login-common.sh PATH="$tmp/installbin:$PREFIX/bin:$PATH" \
    PREFIX="$iprefix" bash "$root/install.sh" >"$tmp/out" 2>&1
assert_ne 0 "$?" 'partial install.sh reported success'
assert_eq 'old' "$(cat "$iprefix/share/termux-penv/env-common.sh")" 'partial install replaced files'
if [ ! -e "$iprefix/bin/termux-penv" ]; then
    pass
else
    fail 'partial install installed the binary'
fi

REPO_ROOT="$root" PATH="$tmp/installbin:$PREFIX/bin:$PATH" \
    PREFIX="$iprefix" bash "$root/install.sh" >"$tmp/out" 2>&1
assert_eq 0 "$?" 'install.sh failed'
assert_file "$iprefix/share/termux-penv/install-common.sh" 'install.sh missing install-common.sh'
assert_file "$iprefix/bin/termux-penv" 'install.sh missing termux-penv'
if [ -L "$iprefix/bin/tp" ]; then
    pass
else
    fail 'install.sh did not create the tp symlink'
fi
assert_eq 'termux-penv' "$(readlink "$iprefix/bin/tp")" 'tp symlink target'

# Legacy v2 directories must be removable with the new command.
case "$host" in
    aarch64|arm*) legacy_arch=arm ;;
    x86_64|i686) legacy_arch=i686 ;;
esac
rm -rf "$program_dir/termux-$legacy_arch" "$program_dir/termux32"
mkdir -p "$program_dir/termux32/usr"
printf 'keep\n' > "$program_dir/termux32/usr/marker"
"$PREFIX/bin/termux-penv" remove termux --arch "$legacy_arch" >"$tmp/out" 2>&1
assert_eq 0 "$?" 'legacy remove failed'
assert_no_dir "$program_dir/termux32" 'legacy directory left behind'

# With no new-style env installed, remove without --arch must clean legacy dirs.
rm -rf "$program_dir/termux-"* "$program_dir/termux32" "$program_dir/termux64"
mkdir -p "$program_dir/termux64/usr"
printf 'keep\n' > "$program_dir/termux64/usr/marker"
"$PREFIX/bin/termux-penv" remove termux >"$tmp/out" 2>&1
assert_eq 0 "$?" 'no-arch legacy remove failed'
assert_no_dir "$program_dir/termux64" 'no-arch legacy directory left behind'

printf '%d checks, %d failures\n' "$checks" "$failures"
[ "$failures" -eq 0 ]
