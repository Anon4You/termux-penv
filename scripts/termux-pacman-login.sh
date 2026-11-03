#!/data/data/com.termux/files/usr/bin/bash

LOGIN_ENV=termux-pacman
LOGIN_PREFIX=pacman
LOGIN_BASE="$PREFIX/var/lib/termux_penv"
. "$(dirname "$0")/login-common.sh"
login_main "$@"
