#!/data/data/com.termux/files/usr/bin/bash

# Shared helpers for termux-penv.

detect_arch() {
    case "$(uname -m)" in
        aarch64|arm64) echo aarch64 ;;
        arm|armv6l|armv7l|armv8l) echo arm ;;
        x86_64|amd64|AMD64) echo x86_64 ;;
        i386|i486|i586|i686) echo i686 ;;
        *) return 1 ;;
    esac
}

validate_arch() {
    case "$1" in
        aarch64|arm|x86_64|i686) return 0 ;;
        *) return 1 ;;
    esac
}

# Rejects symlink targets that could escape the chroot.
is_safe_symlink_dest() {
    case "$1" in
        ''|.|..|/*) return 1 ;;
    esac
    case "/$1/" in
        */../*) return 1 ;;
    esac
    return 0
}

# Warns when a bootstrap URL names another architecture. A URL without an
# architecture token is allowed, since custom archives may use other names.
check_bootstrap_arch() {
    local url="$1" arch="$2" name detected=""

    name="${url%%\?*}"
    name="${name%%#*}"
    name="${name##*/}"

    case "$name" in
        *bootstrap-aarch64*|*bootstrap-arm64*) detected=aarch64 ;;
        *bootstrap-arm.*|*bootstrap-arm-*|*bootstrap-arm_*|bootstrap-arm) detected=arm ;;
        *bootstrap-x86_64*) detected=x86_64 ;;
        *bootstrap-i686*) detected=i686 ;;
    esac

    if [ -n "$detected" ] && [ "$detected" != "$arch" ]; then
        printf "ERROR: bootstrap URL is for %s, not %s: %s\n" "$detected" "$arch" "$name" >&2
        return 1
    fi
    if [ -z "$detected" ]; then
        printf "WARNING: cannot determine bootstrap architecture from '%s'; expected %s.\n" "$name" "$arch" >&2
    fi
    return 0
}

# Removes a chroot directory and verifies it is really gone.
remove_chroot() {
    local dir="$1"
    [ -e "$dir" ] || [ -L "$dir" ] || return 0
    chmod -R u+rwX "$dir" 2>/dev/null || true
    rm -rf "$dir"
    [ ! -e "$dir" ] && [ ! -L "$dir" ]
}

# Sets RESOLVED_ARCH from the requested arch or the installed environments.
# Requires LOGIN_BASE, LOGIN_PREFIX and LOGIN_ENV to be set.
resolve_arch() {
    local requested="$1" host dir name
    local -a found=()

    if [ -n "$requested" ]; then
        validate_arch "$requested" || {
            echo "ERROR: invalid architecture '$requested' (use aarch64, arm, x86_64 or i686)" >&2
            exit 1
        }
        RESOLVED_ARCH="$requested"
        return 0
    fi

    host=$(detect_arch)

    if [ -n "$host" ] && [ -d "$LOGIN_BASE/$LOGIN_PREFIX-$host" ]; then
        RESOLVED_ARCH="$host"
        return 0
    fi

    for dir in "$LOGIN_BASE/$LOGIN_PREFIX-"*; do
        [ -d "$dir" ] || continue
        name=${dir##*/}
        name=${name#"$LOGIN_PREFIX"-}
        validate_arch "$name" && found+=("$name")
    done

    if [ ${#found[@]} -eq 1 ]; then
        RESOLVED_ARCH="${found[0]}"
        return 0
    fi

    if [ ${#found[@]} -eq 0 ]; then
        echo "ERROR: $LOGIN_ENV is not installed." >&2
        if [ -n "$host" ]; then
            echo "Install it with: termux-penv install $LOGIN_ENV --arch $host" >&2
        else
            echo "Install it with: termux-penv install $LOGIN_ENV --arch <arch>" >&2
        fi
        exit 1
    fi

    echo "ERROR: multiple $LOGIN_ENV architectures installed: ${found[*]}" >&2
    echo "Choose one with --arch <arch>." >&2
    exit 1
}

# Prints the download URL of the bootstrap asset for ARCH from a GitHub
# release tag URL. Falls back to the canonical asset URL when the release
# page/API cannot be read. Returns 1 when URL is not a tag URL, and 2 when
# the release has zip assets but none for ARCH.
resolve_github_bootstrap() {
    local url="$1" arch="$2" rest owner repo tag api assets available found

    while [ "${url%/}" != "$url" ]; do
        url="${url%/}"
    done

    case "$url" in
        https://github.com/*/releases/tag/*) ;;
        *) return 1 ;;
    esac

    rest="${url#https://github.com/}"
    owner="${rest%%/*}"
    rest="${rest#*/}"
    repo="${rest%%/releases/tag/*}"
    tag="${url##*/releases/tag/}"
    tag=$(printf '%s' "$tag" | sed 's/+/%2B/g')

    api="https://api.github.com/repos/$owner/$repo/releases/tags/$tag"
    assets=$(curl -s "$api" 2>/dev/null)

    if [ -n "$assets" ]; then
        available=$(printf '%s\n' "$assets" |
            grep -o '"https://[^"]*\.zip"' |
            tr -d '"')
        if [ -n "$available" ]; then
            found=$(printf '%s\n' "$available" |
                grep -E "bootstrap-${arch}([._-][^/]*)?\.zip$" |
                head -1)
            if [ -n "$found" ]; then
                printf '%s\n' "$found"
                return 0
            fi
            printf 'ERROR: release %s/%s tag %s has no bootstrap for %s. Available assets:\n' \
                "$owner" "$repo" "$tag" "$arch" >&2
            while IFS= read -r found; do
                [ -n "$found" ] && printf '  %s\n' "${found##*/}" >&2
            done <<< "$available"
            return 2
        fi
    fi

    printf 'https://github.com/%s/%s/releases/download/%s/bootstrap-%s.zip\n' \
        "$owner" "$repo" "$tag" "$arch"
}
