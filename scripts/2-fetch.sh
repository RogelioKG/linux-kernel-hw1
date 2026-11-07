#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")/.."
K=build/linux-5.15.135

if [ -d $K ]; then
  echo "already fetched"
  exit 0
fi

mkdir -p build
curl -L https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.15.135.tar.xz | tar -xJ -C build
