#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")/.."
K=build/linux-5.15.135

ln -sfn "$PWD/src" $K/kernel/linux_kernel_hw1

if grep -q linux_kernel_hw1 $K/kernel/Makefile; then
  echo "already wired"
  exit 0
fi

echo 'obj-y += linux_kernel_hw1/' >>$K/kernel/Makefile
sed -i '/^448\t/a 449\tcommon\tmy_get_physical_addresses\tsys_my_get_physical_addresses' \
  $K/arch/x86/entry/syscalls/syscall_64.tbl
