#!/bin/sh
# Build Task K: the kernel for the DE25-Nano, cross-compiled for arm64. See kernel/README.md.
#
# Usage: kernel/build.sh
# Output: out/kernel/Image                                   the kernel
#         out/kernel/modules.tar.gz                          its modules, as usr/lib/modules/<release>/
#         out/kernel/dtbs/socfpga_agilex5_de25_nano.dtb      the board's device tree
#         out/kernel/config                                  the configuration used
# Needs: Docker, git, network access to github.com. About 3 GB of disk.
#
# The source is fetched once into work/linux. To build another branch or your own tree, set
# LINUX_BRANCH, or put the tree at work/linux yourself.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
work=$top/work; out=$top/out/kernel
mkdir -p "$work" "$out/dtbs"

LINUX_REPO=${LINUX_REPO:-https://github.com/jclark/linux}
LINUX_BRANCH=${LINUX_BRANCH:-de25-nano-mainline/v7.4-rc2}

[ -d "$work/linux/.git" ] || git clone --depth 1 -b "$LINUX_BRANCH" "$LINUX_REPO" "$work/linux"

docker build -q -t de25-nano-kernel "$top/kernel" >/dev/null
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$top":"$top" -w "$work/linux" de25-nano-kernel sh -euc '
    top="'"$top"'"; obj=$top/work/linux-obj; stage=$top/work/linux-modules
    jobs=$(nproc)
    mk() { make O="$obj" LOCALVERSION=-de25-nano "$@"; }
    # Configuration: arm64 defconfig plus the three options in the fragment.
    mk defconfig
    scripts/kconfig/merge_config.sh -m -O "$obj" "$obj/.config" "$top/kernel/de25-nano.fragment"
    mk olddefconfig
    mk -j"$jobs" Image modules dtbs
    rm -rf "$stage"; mkdir -p "$stage/usr"
    mk INSTALL_MOD_PATH="$stage/usr" INSTALL_MOD_STRIP=1 modules_install
    rel=$(cat "$obj/include/config/kernel.release")
    rm -f "$stage/usr/lib/modules/$rel/build" "$stage/usr/lib/modules/$rel/source"
    tar -C "$stage" -czf "$top/out/kernel/modules.tar.gz" usr
    cp "$obj/arch/arm64/boot/Image" "$top/out/kernel/Image"
    cp "$obj/arch/arm64/boot/dts/intel/socfpga_agilex5_de25_nano.dtb" "$top/out/kernel/dtbs/"
    cp "$obj/.config" "$top/out/kernel/config"
    echo "kernel release: $rel"
'
for o in SENSORS_ALTERA_SOCFPGA_HWMON=y DW_AXI_DMAC=m FB_SIMPLE=y; do
    grep -q "^CONFIG_$o" "$out/config" || { echo "kernel/build.sh: CONFIG_$o is not in the result" >&2; exit 1; }
done
ls -l "$out" "$out/dtbs"
