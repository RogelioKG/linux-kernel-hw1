#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")/.."

boot() {
  qemu-system-x86_64 -enable-kvm -cpu host -m 1G -smp 2 -nographic -no-reboot \
    -kernel build/out/arch/x86/boot/bzImage \
    -drive file=build/rootfs.img,format=raw \
    -append "console=ttyS0 root=/dev/sda rw rootfstype=ext4 init=/usr/sbin/hw1-init panic=-1 $*"
}

if [ "$1" = shell ]; then
  size=$(stty size 2>/dev/null || echo 24 80)
  boot hw1=shell hw1_rows="${size% *}" hw1_cols="${size#* }"
  exit
fi

boot hw1=auto | tee build/qemu.log
grep -E '\[(PASS|FAIL|INCONCLUSIVE|SKIP|WARN)\]|exited with status|Summary' build/qemu.log
