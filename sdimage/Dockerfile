# Build environment for the DE25-Nano SD card image (runs on x86-64 or arm64).
# The host needs qemu-user binfmt registered for aarch64 when it is not arm64.
FROM debian:trixie
RUN apt-get update && apt-get install -y --no-install-recommends \
      mmdebstrap arch-test debian-archive-keyring ca-certificates \
      e2fsprogs dosfstools mtools fdisk uuid-runtime openssl u-boot-tools \
    && rm -rf /var/lib/apt/lists/*
