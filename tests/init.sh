#!/bin/bash
# PID 1 of the guest (/usr/sbin/hw1-init): mount the pseudo filesystems, then
#   hw1=auto  run q1 and q2, then power off
#   otherwise open a root shell on the serial console; power off when it exits
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mountpoint -q /dev || mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /dev/shm
mount -t tmpfs tmpfs /run
hostname hw1
export HOME=/root TERM=linux PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /root

if [ "$hw1" = auto ]; then
  for t in q1 q2; do
    ./$t
    echo "[init] $t exited with status $?"
  done
else
  [ "${hw1_cols:-0}" -gt 0 ] && stty -F /dev/ttyS0 rows "$hw1_rows" cols "$hw1_cols"
  echo "[init] root shell; run ./q1 and ./q2 in /root, leave with poweroff -f"
  setsid -cw bash -l <>/dev/ttyS0 >&0 2>&0
fi

sync
poweroff -f
