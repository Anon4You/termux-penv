#!/data/data/com.termux/files/usr/bin/bash
SCRIPTNAME=termux32login.sh
PROOT=$PREFIX/bin/proot
HOME=$PREFIX/../home
NEWROOT=$PREFIX/var/lib/termux_penv/chroot32/usr

if [ ! -d "$NEWROOT" ]; then
    echo "ERROR: No chroot installed. Install it with termux-penv install termux32"
    exit 1
fi

show_usage() {
    echo "Usage: $SCRIPTNAME [command]"
    echo "termux-penv login termux32: Setup a chroot to use Termux bootstrap in isolated chroot"
    echo ""
    echo "Execute a command in a chroot with traditional file system hierarchy"
    echo "If run without argument, the default shell will be executed"
    exit 0
}

while getopts :h option; do
    case "$option" in
        h) show_usage ;;
        ?) echo "$SCRIPTNAME: illegal option -$OPTARG"; exit 1 ;;
    esac
done
clear
shift $((OPTIND-1))

OLD_LD_PRELOAD=$LD_PRELOAD
unset LD_PRELOAD

ARGS="--kill-on-exit"
ARGS="$ARGS -b /system:/system"
ARGS="$ARGS -b /vendor:/vendor"
ARGS="$ARGS -b /data:/data -b $HOME:/home"
ARGS="$ARGS -b $NEWROOT:/data/data/com.termux/files/usr/"

if [ -d /sbin ] && [ -d /root ]; then
    ARGS="$ARGS -b /sbin:/sbin -b /root:/root"
fi

if [ -d /apex ]; then
    ARGS="$ARGS -b /apex:/apex"
fi

if [ -e "/linkerconfig/ld.config.txt" ]; then
    ARGS="$ARGS -b /linkerconfig/ld.config.txt:/linkerconfig/ld.config.txt"
fi

if [ -f /property_contexts ]; then
    ARGS="$ARGS -b /property_contexts:/property_contexts"
fi

if [ -d /storage ]; then
    ARGS="$ARGS -b /storage:/storage"
fi

ARGS="$ARGS -b $NEWROOT:/usr"

for f in bin etc lib share tmp var; do
    ARGS="$ARGS -b $NEWROOT/$f:/$f"
done

for f in dev proc; do
    ARGS="$ARGS -b /$f:/$f"
done

ARGS="$ARGS --cwd=/home"
ARGS="$ARGS -r $NEWROOT/.."
PROGRAM="bash -c '/usr/bin/login'"
export HOME=/home

if [ -z "$1" ]; then
    ARGS="$ARGS $PROGRAM -l"
    exec $PROOT $ARGS
else
    ARGS="$ARGS --cwd=."
    exec $PROOT $ARGS sh -c "$*"
fi

export LD_PRELOAD=$OLD_LD_PRELOAD
