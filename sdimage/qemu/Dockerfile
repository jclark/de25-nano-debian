# What sdimage/qemu-test.sh needs: QEMU for arm64, ssh, mtools to put files on the image's
# FAT partition, dpkg-deb to take the kernel out of its package.
FROM debian:trixie
RUN apt-get update && apt-get install -y --no-install-recommends \
      qemu-system-arm openssh-client mtools dpkg ca-certificates \
    && rm -rf /var/lib/apt/lists/*
