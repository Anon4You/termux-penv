#!/data/data/com.termux/files/usr/bin/bash

# Small regression suite for termux-penv. Uses fake proot/wget/unzip/curl.

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

check_bootstrap_arch 'https://example/bootstrap-aarch64.zip' aarch64 2>/dev/null && pass ||
    fail 'matching bootstrap arch rejected'
check_bootstrap_arch 'https://example/bootstrap-x86_64.zip' aarch64 2>"$tmp/arch.err" &&
    fail 'mismatched bootstrap arch accepted' || pass
assert_contains 'bootstrap URL is for x86_64, not aarch64' "$tmp/arch.err" 'mismatch error'
check_bootstrap_arch 'https://example/my-bootstrap.zip' aarch64 2>"$tmp/arch.err" && pass ||
    fail 'unnamed bootstrap rejected'
assert_contains 'cannot determine bootstrap architecture' "$tmp/arch.err" 'unnamed warning'

# Resolver: no matching asset must be a hard failure, not a 404 fallback.
curl() {
    printf '%s\n' '{"assets":[{"browser_download_url":"https://example/bootstrap-x86_64.zip"}]}'
}
resolved=$(resolve_github_bootstrap 'https://github.com/o/r/releases/tag/t' aarch64 2>"$tmp/resolve.err")
rc=$?
unset -f curl
assert_eq 2 "$rc" 'no-asset resolver status'
assert_eq '' "$resolved" 'no-asset resolver output'
assert_contains 'has no bootstrap for aarch64' "$tmp/resolve.err" 'no-asset error'
assert_contains 'bootstrap-x86_64.zip' "$tmp/resolve.err" 'available assets'

curl() {
    printf '%s\n' '{"assets":[{"browser_download_url":"https://example/bootstrap-aarch64.zip"}]}'
}
resolved=$(resolve_github_bootstrap 'https://github.com/o/r/releases/tag/t' aarch64 2>/dev/null)
rc=$?
unset -f curl
assert_eq 0 "$rc" 'matching asset status'
assert_eq 'https://example/bootstrap-aarch64.zip' "$resolved" 'matching asset URL'
resolve_github_bootstrap 'https://example/bootstrap.zip' aarch64 >/dev/null 2>&1
assert_eq 1 "$?" 'direct zip status'
curl() { return 1; }
resolved=$(resolve_github_bootstrap 'https://github.com/o/r/releases/tag/t+1' aarch64 2>/dev/null)
rc=$?
unset -f curl
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
cat > "$tmp/nomatch/curl" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
printf '%s\n' '{"assets":[{"browser_download_url":"https://example/bootstrap-x86_64.zip"}]}'
EOF
chmod +x "$tmp/nomatch/curl"
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
PATH="$tmp/malbin:$tmp/fakebin:$PATH" bash "$share/termux-install.sh" --arch x86_64 \
    --bootstrap 'https://example/bootstrap-x86_64.zip' >"$tmp/out" 2>&1
assert_eq 0 "$?" 'symlink install failed'
if [ ! -e "$program_dir/escape" ] && [ ! -L "$program_dir/escape" ]; then
    pass
else
    fail 'unsafe symlink escaped the chroot'
fi

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

printf '%d checks, %d failures\n' "$checks" "$failures"
[ "$failures" -eq 0 ]
