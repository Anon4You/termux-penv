#!/data/data/com.termux/files/usr/bin/bash
printf "> Removing 32 bit termux environment\n"
sleep 1
if [[ -d $PREFIX/var/lib/termux_penv/chroot32/ ]]; then
  rm -rf $PREFIX/var/lib/termux_penv/chroot32/
  printf "32 bit termux environment removed\n"
else
  printf "32 bit termux environment not installed\n install it by executing termux-penv install termux32\n"
fi
