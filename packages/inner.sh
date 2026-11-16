#!/bin/sh
# Runs inside the packaging container (packages/build.sh, packages/mkdeb-core). Makes one
# binary package with dpkg-deb from files that are already built; there is nothing to compile.
#
#   inner.sh tools VERSION OUTDIR
#   inner.sh boot  NAME VERSION ITB RPD OUTDIR
#   inner.sh core  NAME BOOT VERSION INDIR OUTDIR     INDIR holds fpga.rbf and fpga.dtbo
set -eu
here=$(cd "$(dirname "$0")" && pwd)
maint="de25-nano-debian project <de25-nano-debian@users.noreply.github.com>"
home=https://github.com/jclark/de25-nano-debian
stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
chmod 755 "$stage"; mkdir -p "$stage/DEBIAN"

control() {   # control PACKAGE VERSION ARCH DEPENDS SYNOPSIS; the long description on stdin
    {
        echo "Package: $1"
        echo "Version: $2"
        echo "Architecture: $3"
        echo "Maintainer: $maint"
        echo "Installed-Size: $(du -sk --exclude=DEBIAN "$stage" | cut -f1)"
        [ -z "$4" ] || echo "Depends: $4"
        echo "Section: admin"
        echo "Priority: optional"
        echo "Homepage: $home"
        echo "Description: $5"
        sed -e 's/^$/./' -e 's/^/ /'
    } > "$stage/DEBIAN/control"
}
script() {    # script NAME: a maintainer script, from stdin
    { printf '#!/bin/sh\nset -e\n'; cat; } > "$stage/DEBIAN/$1"
    chmod 755 "$stage/DEBIAN/$1"
}
copyright() { # copyright PACKAGE: /usr/share/doc/PACKAGE/copyright, from stdin
    install -d "$stage/usr/share/doc/$1"
    cat > "$stage/usr/share/doc/$1/copyright"
}
finish() {    # finish PACKAGE VERSION ARCH OUTDIR
    mkdir -p "$4"
    deb=$4/$1_$2_$3.deb
    rm -f "$deb"
    dpkg-deb --root-owner-group -Zxz --build "$stage" "$deb" >/dev/null
    echo "$deb"
}

kind=$1; shift
case $kind in
tools)
    version=$1; out=$2
    t=$here/fpga-tools
    install -d "$stage/usr/sbin" "$stage/usr/lib/de25-nano" "$stage/usr/lib/udev/rules.d" \
        "$stage/usr/lib/systemd/system" "$stage/etc/default" "$stage/usr/share/man/man8"
    install -m 755 "$t/de25-fpga" "$t/de25-flash" "$t/de25-fan-curve" "$t/de25-hdmi-init" "$stage/usr/sbin/"
    install -m 644 "$t/common.sh" "$stage/usr/lib/de25-nano/common.sh"
    install -m 644 "$t/60-de25-fan.rules" "$stage/usr/lib/udev/rules.d/60-de25-fan.rules"
    install -m 644 "$t/de25-hdmi-init.service" "$stage/usr/lib/systemd/system/de25-hdmi-init.service"
    install -m 644 "$t/de25-fan.default" "$stage/etc/default/de25-fan"
    for m in de25-fpga de25-flash; do
        gzip -9n -c "$t/man/$m.8" > "$stage/usr/share/man/man8/$m.8.gz"
    done
    echo /etc/default/de25-fan > "$stage/DEBIAN/conffiles"
    copyright de25-nano-fpga-tools < "$here/../LICENSE"
    script postinst <<'EOF'
if [ "$1" = configure ]; then
    systemctl enable de25-hdmi-init.service >/dev/null 2>&1 || true
    if [ -d /run/systemd/system ]; then
        systemctl daemon-reload || true
        udevadm control --reload || true
    fi
fi
EOF
    script prerm <<'EOF'
if [ "$1" = remove ]; then
    systemctl disable de25-hdmi-init.service >/dev/null 2>&1 || true
fi
EOF
    control de25-nano-fpga-tools "$version" all "u-boot-menu, mtd-utils, i2c-tools, kmod" \
        "DE25-Nano: commands for the flash and the FPGA core image" <<'EOF'
de25-flash writes the board's flash, which holds the HPS image, and keeps U-Boot on
the SD card in step with it. de25-fpga chooses the core image that U-Boot loads into
the FPGA at boot.

Also here: the udev rule, script and settings that set the fan curve, and the script
and unit that set up the HDMI transmitter. They do nothing until a core image that
connects those chips is loaded.
EOF
    finish de25-nano-fpga-tools "$version" all "$out"
    ;;
boot)
    name=$1; version=$2; itb=$3; rpd=$4; out=$5
    d=$stage/usr/lib/de25-nano/boot/$name
    install -d "$d"
    install -m 644 "$itb" "$d/u-boot.itb"
    install -m 644 "$rpd" "$d/hps.rpd"
    mkimage -A arm64 -T script -C none -n "DE25-Nano boot script" -d "$here/boot/boot.cmd" "$d/boot.scr" >/dev/null
    chmod 644 "$d/boot.scr"
    copyright "de25-nano-boot-$name" <<EOF
u-boot.itb holds U-Boot (GPL-2.0-or-later) and TF-A (BSD-3-Clause), built from Terasic's
sources at the commits named in u-boot/build.sh of $home,
with the patch and configuration fragment in that directory. hps.rpd holds U-Boot's SPL
from the same build and the SoC configuration of the FPGA design in fpga/ of that
repository, which is Altera's reference design (MIT) with the changes there (MIT).
boot.scr is packages/boot/boot.cmd of that repository (MIT).
EOF
    script postinst <<'EOF'
# Renew u-boot.itb and boot.scr on the card, if the flash already holds this HPS image.
# The flash is never written here: that is "de25-flash write".
if [ "$1" = configure ]; then
    de25-flash sync || true
fi
EOF
    control "de25-nano-boot-$name" "$version" arm64 "de25-nano-fpga-tools (>= 0.2)" \
        "DE25-Nano: HPS image for the flash, with its U-Boot ($name)" <<EOF
What a DE25-Nano runs before the kernel, built together: the HPS image for the board's
flash (the SoC's settings and U-Boot's SPL), and the u-boot.itb and boot.scr that go on
the SD card's FAT partition.

Installing this package does not write the flash. "de25-flash write" does, and puts
u-boot.itb and boot.scr on the card with it. When the flash already holds this HPS
image, an upgrade renews the two files on the card by itself.

Core images (packages de25-nano-core-...) built for the SoC settings named "$name"
load on this HPS image.
EOF
    finish "de25-nano-boot-$name" "$version" arm64 "$out"
    ;;
core)
    name=$1; boot=$2; version=$3; in=$4; out=$5
    d=$stage/usr/lib/de25-nano/core/$name
    install -d "$d"
    install -m 644 "$in/fpga.rbf" "$in/fpga.dtbo" "$d/"
    echo "$boot" > "$d/boot"
    if [ -f "$in/copyright" ]; then
        copyright "de25-nano-core-$name" < "$in/copyright"
    else
        copyright "de25-nano-core-$name" <<EOF
fpga.rbf is built with Altera's Quartus Prime Pro from Altera's reference design for the
board (MIT) with the changes in fpga/ of $home (MIT).
EOF
    fi
    script postinst <<EOF
# If this core is the selected one, put the new version where the boot uses it.
if [ "\$1" = configure ]; then
    de25-fpga hook configure $name || true
fi
EOF
    script prerm <<EOF
if [ "\$1" = remove ]; then
    de25-fpga hook remove $name || true
fi
EOF
    control "de25-nano-core-$name" "$version" arm64 "de25-nano-boot-$boot, de25-nano-fpga-tools (>= 0.2)" \
        "DE25-Nano: FPGA core image ($name)" <<EOF
A core image for the DE25-Nano's FPGA, with its device tree overlay. U-Boot loads the
selected core image at boot; "de25-fpga select $name" selects this one. It loads on the
HPS image of de25-nano-boot-$boot.
${DESCRIPTION:+
$DESCRIPTION}
EOF
    finish "de25-nano-core-$name" "$version" arm64 "$out"
    ;;
*)
    echo "inner.sh: unknown kind $kind" >&2; exit 2
    ;;
esac
