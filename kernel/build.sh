#!/bin/sh
# Build Task K: the kernel for the DE25-Nano as a Debian package, cross-compiled for arm64.
# See kernel/README.md.
#
# Usage: kernel/build.sh
# Output: out/kernel/linux-image-<release>_<version>_arm64.deb
#             the kernel, its modules and its device trees, as the kernel's own
#             "make bindeb-pkg" packages them
#         out/kernel/config    the configuration used
# Needs: Docker, git, network access to github.com. About 5 GB of disk.
#
# The source is fetched once into work/linux. To build another branch or your own tree, set
# LINUX_BRANCH, or put the tree at work/linux yourself.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
work=$top/work; out=$top/out/kernel
mkdir -p "$work" "$out"

LINUX_REPO=${LINUX_REPO:-https://github.com/jclark/linux}
LINUX_BRANCH=${LINUX_BRANCH:-de25-nano-mainline/v7.4}

[ -d "$work/linux/.git" ] || git clone --depth 1 -b "$LINUX_BRANCH" "$LINUX_REPO" "$work/linux"

# The date of the source's last commit goes into the kernel's release name, before the commit
# id that the kernel build adds: 7.4.0-rc2-de25-nano-20261113-g6f97abefdd47. Releases then
# sort by age, so that on the board the newest installed kernel is the boot menu's default.
stamp=$(git -C "$work/linux" log -1 --format=%cd --date=format:%Y%m%d)

# Packages of an earlier build would be picked up below.
rm -f "$work"/linux-image-*.deb "$work"/linux-libc-dev_*.deb "$work"/linux-upstream_*

docker build -q -t de25-nano-kernel "$top/kernel" >/dev/null
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$top":"$top" -w "$work/linux" de25-nano-kernel sh -euc '
    top="'"$top"'"; obj=$top/work/linux-obj
    jobs=$(nproc)
    # KBUILD_BUILD_USER, KBUILD_BUILD_HOST: the kernel records who built it and where, and the
    # packaging wants a user name, which the user in the container does not have.
    mk() { make O="$obj" LOCALVERSION=-de25-nano-'"$stamp"' \
               KBUILD_BUILD_USER=build KBUILD_BUILD_HOST=de25-nano-debian "$@"; }
    # Configuration: arm64 defconfig plus the three options in the fragment.
    mk defconfig
    scripts/kconfig/merge_config.sh -m -O "$obj" "$obj/.config" "$top/kernel/de25-nano.fragment"
    mk olddefconfig
    # Build profiles: no linux-headers package (it would need arm64 libraries on the build
    # machine) and no debug symbols package (large).
    DEB_BUILD_PROFILES="pkg.linux-upstream.nokernelheaders pkg.linux-upstream.nokerneldbg" \
    KDEB_CHANGELOG_DIST=trixie DEBFULLNAME="Local build" DEBEMAIL=nobody@localhost \
        mk -j"$jobs" bindeb-pkg
    cp "$obj/.config" "$top/out/kernel/config"
    echo "kernel release: $(cat "$obj/include/config/kernel.release")"
'
# dpkg-buildpackage leaves the packages beside the build directory.
rm -f "$out"/linux-image-*.deb
deb=$(ls "$work"/linux-image-*_arm64.deb 2>/dev/null | grep -v -- '-dbg_' | head -n 1)
[ -n "$deb" ] || { echo "kernel/build.sh: no linux-image package in $work" >&2; exit 1; }
cp "$deb" "$out/"
for o in SENSORS_ALTERA_SOCFPGA_HWMON=y DW_AXI_DMAC=m FB_SIMPLE=y; do
    grep -q "^CONFIG_$o" "$out/config" || { echo "kernel/build.sh: CONFIG_$o is not in the result" >&2; exit 1; }
done
ls -l "$out"
