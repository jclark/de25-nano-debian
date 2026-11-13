# Altera's Quartus Pro image plus what the reference design's Makefile and the
# licence fetch need (the base image has no CA certificates, make or git).
FROM alterafpga/quartus-pro:26.1.1-agilex5
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates make git zip unzip python3 cmake curl file strace \
    && rm -rf /var/lib/apt/lists/*

# RISC-V bare-metal GCC for the reference design's Nios V firmware (Altera ships
# this in RiscFree, which the base image lacks). xPack's compiler is named
# riscv-none-elf-*; the Nios V BSP expects riscv32-unknown-elf-*.
ARG XPACK=14.2.0-3
RUN cd /tmp && f=xpack-riscv-none-elf-gcc-${XPACK}-linux-x64.tar.gz \
    && u=https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK} \
    && curl -fsSL -O $u/$f -O $u/$f.sha && sha256sum -c $f.sha \
    && mkdir -p /opt/xpack && tar -xzf $f -C /opt/xpack --strip-components=1 && rm $f $f.sha \
    && for t in /opt/xpack/bin/riscv-none-elf-*; do \
         ln -s $t /usr/local/bin/riscv32-unknown-elf-${t##*/riscv-none-elf-}; done
COPY riscv-wrap /usr/local/bin/riscv-wrap
RUN for t in gcc g++ as; do ln -sf riscv-wrap /usr/local/bin/riscv32-unknown-elf-$t; done

# patch: fpga/apply.sh uses it. device-tree-compiler: dtc, for fpga/overlay/build.sh.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends patch device-tree-compiler \
    && rm -rf /var/lib/apt/lists/*
