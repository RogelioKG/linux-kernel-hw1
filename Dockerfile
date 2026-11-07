FROM ubuntu:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential bc bison flex libelf-dev libssl-dev \
  && rm -rf /var/lib/apt/lists/*
