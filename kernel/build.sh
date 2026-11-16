#!/bin/sh
# Build Task K: the kernel for the DE25-Nano as a Debian package, cross-compiled for arm64.
# See kernel/README.md.
#
# Usage: kernel/build.sh
# Output: out/kernel/linux-image-<release>_<version>_arm64.deb
#             the kernel, its modules and its device trees, as the kernel's own
#             "make bindeb-pkg" packages them
#         out/kernel/config    the configuration used
# Needs: git and network access to github.com; the tools of kernel/Dockerfile on this machine,
#        or else Docker. About 5 GB of disk.
#
# The source is fetched into work/linux, and a later run brings that clone up to the head of
# the branch. To build another branch, set LINUX_BRANCH and delete work/linux; to build your
# own tree, put it at work/linux yourself: a tree that is not an unchanged clone of the branch
# is built as it is.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
work=$top/work; out=$top/out/kernel
mkdir -p "$work" "$out"

LINUX_REPO=${LINUX_REPO:-https://github.com/jclark/linux}
LINUX_BRANCH=${LINUX_BRANCH:-de25-nano-mainline/v7.4}

if [ ! -d "$work/linux/.git" ]; then
    git clone --depth 1 -b "$LINUX_BRANCH" "$LINUX_REPO" "$work/linux"
elif [ "$(git -C "$work/linux" remote get-url origin 2>/dev/null)" = "$LINUX_REPO" ] &&
     [ "$(git -C "$work/linux" rev-parse --abbrev-ref HEAD)" = "$LINUX_BRANCH" ] &&
     [ -z "$(git -C "$work/linux" status --porcelain --untracked-files=no)" ]; then
    # The branch moves forward (kernel/README.md): bring the clone this script made up to it.
    git -C "$work/linux" fetch --depth 1 origin "$LINUX_BRANCH"
    git -C "$work/linux" reset -q --hard FETCH_HEAD
else
    echo "kernel/build.sh: work/linux is not an unchanged clone of $LINUX_REPO $LINUX_BRANCH: building it as it is"
fi
git -C "$work/linux" log -1 --format='kernel source: %h %s'

# The date of the source's last commit goes into the kernel's release name, before the commit
# id that the kernel build adds: 7.4.0-rc2-de25-nano-20261113-g6f97abefdd47. Releases then
# sort by age, so that on the board the newest installed kernel is the boot menu's default.
stamp=$(git -C "$work/linux" log -1 --format=%cd --date=format:%Y%m%d)

# Packages of an earlier build would be picked up below.
rm -f "$work"/linux-image-*.deb "$work"/linux-libc-dev_*.deb "$work"/linux-upstream_*

# What is run, on this machine or in the container.
build='
    obj=$top/work/linux-obj
    jobs=$(nproc)
    # KBUILD_BUILD_USER, KBUILD_BUILD_HOST: the kernel records who built it and where, and the
    # packaging wants a user name, which the user in the container does not have.
    mk() { make O="$obj" LOCALVERSION=-de25-nano-$stamp \
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
# With the compiler and the other tools of kernel/Dockerfile on this machine, build here;
# otherwise in the container.
native=yes
case $(uname -m) in
    aarch64) cross= ;;
    *) cross=aarch64-linux-gnu-; command -v ${cross}gcc >/dev/null || native=no ;;
esac
for t in gcc make bc bison flex dpkg-buildpackage dh rsync cpio; do
    command -v $t >/dev/null || native=no
done
[ -f /usr/include/libelf.h ] && [ -f /usr/include/openssl/ssl.h ] || native=no
# The kernel installs its device trees with many "install -D" at once. GNU's install copes
# with two of them making the same directory; the one in uutils coreutils 0.10 (Ubuntu's
# default) fails. Where install is not GNU's, use gnuinstall if the machine has it.
if [ $native = yes ] && ! install --version 2>/dev/null | grep -q 'GNU coreutils'; then
    if command -v gnuinstall >/dev/null; then
        mkdir -p "$work/gnu-bin"
        ln -sf "$(command -v gnuinstall)" "$work/gnu-bin/install"
        PATH=$work/gnu-bin:$PATH
    else
        native=no
    fi
fi
if [ $native = yes ]; then
    echo "kernel/build.sh: building on this machine, with $(${cross}gcc --version | head -n 1)"
    (cd "$work/linux" && top=$top stamp=$stamp ARCH=arm64 CROSS_COMPILE=$cross sh -euc "$build")
else
    echo "kernel/build.sh: building in the container (not every tool of kernel/Dockerfile is on this machine)"
    docker build -q -t de25-nano-kernel "$top/kernel" >/dev/null
    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e top="$top" -e stamp="$stamp" \
        -v "$top":"$top" -w "$work/linux" de25-nano-kernel sh -euc "$build"
fi
# dpkg-buildpackage leaves the packages beside the build directory.
rm -f "$out"/linux-image-*.deb
deb=$(ls "$work"/linux-image-*_arm64.deb 2>/dev/null | grep -v -- '-dbg_' | head -n 1)
[ -n "$deb" ] || { echo "kernel/build.sh: no linux-image package in $work" >&2; exit 1; }
cp "$deb" "$out/"
for o in SENSORS_ALTERA_SOCFPGA_HWMON=y DW_AXI_DMAC=m FB_SIMPLE=y; do
    grep -q "^CONFIG_$o" "$out/config" || { echo "kernel/build.sh: CONFIG_$o is not in the result" >&2; exit 1; }
done
ls -l "$out"
