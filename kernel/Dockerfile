# Build environment for the DE25-Nano kernel: Debian with the arm64 cross-compiler.
FROM debian:trixie
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential gcc-aarch64-linux-gnu bc bison flex libssl-dev libelf-dev \
      kmod cpio rsync python3 perl xz-utils git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
ENV ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
