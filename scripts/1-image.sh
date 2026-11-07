#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")/.."

docker build -t linux-kernel-hw1-builder - <Dockerfile
scripts/rootfs.sh
