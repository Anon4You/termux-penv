#!/data/data/com.termux/files/usr/bin/bash
printf "> Removing 64 bit termux environment\n"
sleep 1
if [[ -d $PREFIX/var/lib/termux_penv/chroot64 ]]; then
  rm -rf $PREFIX/var/lib/termux_penv/chroot64
  printf "64 bit termux environment removed\n"
else
  printf "64 bit termux environment not installed\n install it by executing termux-penv install termux64\n"
fi
