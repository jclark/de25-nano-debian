# Build environment for the DE25-Nano kernel: Debian 13 with the arm64 cross-compiler and
# what the kernel's own Debian packaging (make bindeb-pkg) needs.
FROM debian:trixie
# build-essential, gcc-aarch64-linux-gnu: the compilers (the kernel's build tools run on the
#   build machine; the kernel itself is compiled for arm64)
# bc bison flex kmod libdw-dev libelf-dev libssl-dev python3 rsync: what the kernel's
#   packaging names as build dependencies
# debhelper dpkg-dev: dpkg-buildpackage and the debhelper commands the packaging uses
# cpio perl xz-utils: used by parts of the kernel build
# git ca-certificates: the kernel build reads the source's git state for the release name
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential gcc-aarch64-linux-gnu \
      bc bison flex kmod libdw-dev libelf-dev libssl-dev python3 rsync \
      debhelper dpkg-dev \
      cpio perl xz-utils \
      git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
ENV ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
