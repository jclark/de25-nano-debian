# Build environment for Terasic's TF-A and U-Boot for the DE25-Nano, as in
# Terasic's "Build Linux image from scratch" guide: Ubuntu 22.04 and the
# Arm GNU 11.2 aarch64-none-linux-gnu cross-compiler.
FROM ubuntu:22.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    make bison flex python3-dev python3-setuptools libssl-dev swig u-boot-tools git \
    build-essential bc device-tree-compiler ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN cd /opt && f=gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz \
    && curl -fsSL -O https://developer.arm.com/-/media/Files/downloads/gnu/11.2-2022.02/binrel/$f \
    && tar xf $f && rm $f
ENV PATH=/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin:$PATH \
    ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu-
