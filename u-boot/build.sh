#!/bin/sh
# Build Task B: TF-A and U-Boot for the DE25-Nano. See u-boot/README.md.
#
# Usage: u-boot/build.sh
# Output: out/u-boot/u-boot.itb            U-Boot with TF-A's bl31.bin inside, for the SD card
#         out/u-boot/u-boot-spl-dtb.hex    U-Boot's first stage, the SPL, for the HPS image (fpga/)
# Needs: Docker, git, and network access to github.com and developer.arm.com.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
work=$top/work; out=$top/out/u-boot
mkdir -p "$work" "$out"

# Terasic's sources, at the commits the board's factory loader was built from.
TFA_REPO=https://github.com/terasic/arm-trusted-firmware
TFA_BRANCH=de25-nano-v2.12.0
TFA_COMMIT=580dcb5c4e10aa7daff2bf69d493c076a6d3e665
UBOOT_REPO=https://github.com/terasic/u-boot-socfpga
UBOOT_BRANCH=de25-nano-v2025.01
UBOOT_COMMIT=d0f8813fd6bf8191d49c8b8d2035ffd2ae10c413

fetch() {   # fetch DIR REPO BRANCH COMMIT
    if [ ! -d "$work/$1/.git" ]; then
        git clone --depth 1 -b "$3" "$2" "$work/$1"
    fi
    have=$(git -C "$work/$1" rev-parse HEAD)
    [ "$have" = "$4" ] || {
        echo "u-boot/build.sh: $work/$1 is at $have, expected $4 (has branch $3 moved?)" >&2
        exit 1
    }
}
fetch arm-trusted-firmware "$TFA_REPO" "$TFA_BRANCH" "$TFA_COMMIT"
fetch u-boot-socfpga "$UBOOT_REPO" "$UBOOT_BRANCH" "$UBOOT_COMMIT"

# The change to Terasic's U-Boot source (README.md, Source), applied to clean files each time.
git -C "$work/u-boot-socfpga" checkout -q -- .
git -C "$work/u-boot-socfpga" apply "$top/u-boot/qspi-flash.patch"

docker build -q -t de25-nano-uboot "$top/u-boot" >/dev/null
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$top":"$top" -w "$work" de25-nano-uboot sh -euc '
    jobs=$(nproc)
    # TF-A first: U-Boot packs its bl31.bin into u-boot.itb.
    make -C arm-trusted-firmware -j"$jobs" PLAT=agilex5 bl31
    cd u-boot-socfpga
    ln -sf ../arm-trusted-firmware/build/agilex5/release/bl31.bin .
    make socfpga_agilex5_de25_nano_defconfig
    scripts/kconfig/merge_config.sh -m .config "'"$top"'/u-boot/de25-nano.fragment"
    make olddefconfig
    make -j"$jobs"
'
cp "$work/u-boot-socfpga/u-boot.itb" "$work/u-boot-socfpga/spl/u-boot-spl-dtb.hex" "$out/"
for opt in CONFIG_OF_LIBFDT_OVERLAY CONFIG_OF_BOARD_SETUP CONFIG_LED_SW_BLINK CONFIG_CMD_LED CONFIG_CMD_HASH; do
    grep -q "^$opt=y" "$work/u-boot-socfpga/.config" || {
        echo "u-boot/build.sh: the config fragment did not take effect ($opt)" >&2; exit 1; }
done
ls -l "$out"
