#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")/.."
K=build/linux-5.15.135
O="$PWD/build/out"

scripts/in-docker.sh make -C $K O="$O" -j"$(nproc)" bzImage
scripts/in-docker.sh gcc -Wall -Wextra -O2 tests/q1.c -o build/q1
scripts/in-docker.sh gcc -Wall -Wextra -O2 tests/q2.c -o build/q2 -ldl
scripts/in-docker.sh e2fsck -p build/rootfs.img || [ $? -le 1 ]
scripts/in-docker.sh debugfs -w -f tests/rootfs.debugfs build/rootfs.img
