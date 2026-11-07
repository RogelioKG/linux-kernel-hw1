#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")/.."
K=build/linux-5.15.135
O="$PWD/build/out"

scripts/in-docker.sh make -C $K O="$O" defconfig
$K/scripts/config --file "$O/.config" \
  -e TRANSPARENT_HUGEPAGE -d TRANSPARENT_HUGEPAGE_ALWAYS -e TRANSPARENT_HUGEPAGE_MADVISE \
  -e PROC_PAGE_MONITOR
scripts/in-docker.sh make -C $K O="$O" olddefconfig
