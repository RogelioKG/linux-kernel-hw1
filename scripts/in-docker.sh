#!/usr/bin/env bash
exec docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:$PWD" -w "$PWD" \
  -e KBUILD_BUILD_USER="$USER" linux-kernel-hw1-builder "$@"
