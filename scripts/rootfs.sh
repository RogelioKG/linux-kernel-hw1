#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")/.."

mkdir -p build
cid=$(docker create linux-kernel-hw1-builder)
docker export "$cid" | docker run --rm -i -v "$PWD:$PWD" -w "$PWD" linux-kernel-hw1-builder sh -ec "
  mkdir /rootfs && tar -xp -C /rootfs && rm -f /rootfs/.dockerenv
  echo hw1 > /rootfs/etc/hostname
  gcc -Wall -Wextra -O2 tests/poweroff.c -o /rootfs/usr/sbin/poweroff
  mkfs.ext4 -q -L rootfs -d /rootfs build/rootfs.img.tmp 2G
  chown $(id -u):$(id -g) build/rootfs.img.tmp"
docker rm "$cid"
mv build/rootfs.img.tmp build/rootfs.img
