#!/bin/sh
# Host build dependencies for the Orange Pi 5 Ubuntu 26.10 image build
set -e
sudo apt-get update
sudo apt-get install -y \
  build-essential gcc-aarch64-linux-gnu bison flex bc libssl-dev libelf-dev dwarves \
  dpkg-dev debhelper libdw-dev rsync kmod cpio device-tree-compiler \
  python3-pyelftools python3-setuptools python3-dev swig libgnutls28-dev uuid-dev libncurses-dev \
  mmdebstrap qemu-user-binfmt arch-test \
  e2fsprogs dosfstools fdisk xz-utils zstd
