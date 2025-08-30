#!/data/data/com.termux/files/usr/bin/bash
printf "> Removing 32 bit termux pacman environment\n"
sleep 1
if [[ -d $PREFIX/var/lib/termux_penv/pacman-chroot32/ ]]; then
  rm -rf $PREFIX/var/lib/termux_penv/pacman-chroot32
  printf "32 bit termux pacman environment removed\n"
else
  printf "32 bit termux pacman environment not installed\n install it by executing termux-penv install termux-pacman32\n"
fi
