#!/bin/sh
# Runs inside the build container as root. Called by build-image; see that file for the inputs.
# Produces /out/$IMAGE_NAME: MBR; partition 1 FAT (/boot/firmware: U-Boot and its boot script);
# partition 2 ext4 (/, with the kernel and the boot menu in /boot, and this repository's
# packages installed: the commands, and with them the boot package and the base core in
# /usr/lib/de25-nano, the core not yet selected).
set -eu

: "${SUITE:=trixie}" "${HOSTNAME_:=de25-nano}" "${USER_:=debian}" "${IMAGE_NAME:=de25-nano.img}"
: "${IMAGE_MB:=1024}" "${FAT_MB:=64}" "${DISK_ID:=0xde250001}" "${MAC:=}"
: "${OWNER:=0:0}"

DEB=$(ls /in/linux-image-*_arm64.deb 2>/dev/null | head -1)
[ -n "$DEB" ] || { echo "no linux-image-*_arm64.deb in the input directory" >&2; exit 1; }
KREL=$(dpkg-deb -f "$DEB" Package | sed 's/^linux-image-//')
DTB=intel/socfpga_agilex5_de25_nano.dtb    # under the package's device tree directory; fdtfile in boot.cmd
TOOLS=$(ls /in/de25-nano-fpga-tools_*.deb 2>/dev/null | head -1)
[ -n "$TOOLS" ] || { echo "no de25-nano-fpga-tools_*.deb in the input directory" >&2; exit 1; }
# The boot package and the core packages: both or neither.
BOOT=$(ls /in/de25-nano-boot-*.deb 2>/dev/null | head -1)
CORES=$(ls /in/de25-nano-core-*.deb 2>/dev/null || true)
FABRIC=no
if [ -n "$BOOT" ] || [ -n "$CORES" ]; then
  [ -n "$BOOT" ] && [ -n "$CORES" ] || { echo "a boot package and a core package go together" >&2; exit 1; }
  FABRIC=yes
  BOOT_NAME=$(dpkg-deb -f "$BOOT" Package | sed 's/^de25-nano-boot-//')
else
  [ -f /in/u-boot.itb ] && [ -f /in/boot.cmd ] || { echo "without a boot package, u-boot.itb and boot.cmd are needed" >&2; exit 1; }
fi
PARTUUID_ROOT=$(printf '%08x-02' "$DISK_ID")
PARTUUID_FAT=$(printf '%08x-01' "$DISK_ID")
echo "kernel release $KREL, boot package and core in the image: $FABRIC, root PARTUUID=$PARTUUID_ROOT"

work=/work; root=$work/root
mkdir -p "$work"; find "$work" -mindepth 1 -maxdepth 1 -exec rm -rf {} +; mkdir -p "$root"

# 1. Debian root filesystem from the archive.
mmdebstrap --architectures=arm64 --variant=important \
  --include=systemd-sysv,systemd-resolved,chrony,udev,kmod,openssh-server,sudo,ca-certificates,locales,iproute2,iputils-ping,ethtool,pciutils,usbutils,less,vim-tiny,curl,fdisk,cloud-guest-utils,e2fsprogs,dosfstools,dbus,libnss-systemd,i2c-tools,linuxptp,mtd-utils,u-boot-menu,man-db \
  "$SUITE" "$root"

# 2. What the boot menu is written from, before the kernel is installed: installing a kernel
# package runs Debian's u-boot-update (package u-boot-menu), which writes
# /boot/extlinux/extlinux.conf with an entry for every installed kernel. It takes the root
# file system from /etc/fstab, the kernel command line and other settings from
# /etc/default/u-boot, the device tree directory of each kernel from its package
# (/usr/lib/linux-image-<release>/), and every overlay it finds in /boot/dtbo.
mkdir -p "$root/boot/firmware" "$root/boot/dtbo"
cat > "$root/etc/fstab" <<EOF
PARTUUID=$PARTUUID_ROOT  /               ext4  defaults,noatime  0 1
PARTUUID=$PARTUUID_FAT  /boot/firmware  vfat  defaults,noatime  0 2
EOF
install -m 644 /sd/files/u-boot.default "$root/etc/default/u-boot"

# 3. The kernel package: kernel, modules, device trees.
cp "$DEB" "$root/tmp/kernel.deb"
chroot "$root" dpkg -i /tmp/kernel.deb
rm -f "$root/tmp/kernel.deb"
chroot "$root" u-boot-update
[ -f "$root/usr/lib/linux-image-$KREL/$DTB" ] || { echo "the kernel package has no $DTB" >&2; exit 1; }
menu=$root/boot/extlinux/extlinux.conf
grep -q "fdtdir /usr/lib/linux-image-$KREL/" "$menu" || { echo "the boot menu has no fdtdir line for $KREL" >&2; exit 1; }
cat "$menu"

# 3a. This repository's packages (packages/README.md).
# de25-nano-fpga-tools: de25-flash and de25-fpga, and what a core needs in Linux: the fan
# curve's udev rule, script and settings, and the HDMI transmitter's script and unit. Those do
# nothing without a core: the udev rule waits for the fan controller, and the HDMI unit has a
# condition on the I2C bus that the overlay enables.
# de25-nano-boot-<name>: the HPS image for the flash, with its u-boot.itb and boot.scr.
# de25-nano-core-<name>: a core image and its overlay.
# Their files stay in /usr/lib/de25-nano, out of the way of the boot, until "de25-flash write"
# and "de25-fpga select" are run on the board. (Their maintainer scripts do nothing here:
# /boot/firmware is not mounted.)
mkdir -p "$root/tmp/debs"
cp "$TOOLS" "$root/tmp/debs/"
if [ "$FABRIC" = yes ]; then cp "$BOOT" $CORES "$root/tmp/debs/"; fi
chroot "$root" sh -c 'dpkg -i /tmp/debs/*.deb'
rm -rf "$root/tmp/debs"
chroot "$root" systemctl is-enabled de25-hdmi-init.service >/dev/null || { echo "de25-hdmi-init.service is not enabled" >&2; exit 1; }

# 4. System configuration.
echo "$HOSTNAME_" > "$root/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n::1\tlocalhost ip6-localhost ip6-loopback\n' "$HOSTNAME_" > "$root/etc/hosts"
mkdir -p "$root/etc/systemd/network"
cat > "$root/etc/systemd/network/20-wired.network" <<EOF
[Match]
Type=ether

[Network]
DHCP=yes
EOF
if [ -n "$MAC" ]; then
  # The board has no stored MAC address and U-Boot invents one at each boot. A link file that
  # matches replaces Debian's default one, so the default naming policy is restated: the
  # interface keeps its usual Debian name, end0.
  cat > "$root/etc/systemd/network/10-emac0.link" <<EOF
[Match]
Path=platform-10810000.ethernet

[Link]
MACAddress=$MAC
NamePolicy=keep kernel database onboard slot path
AlternativeNamesPolicy=database onboard slot path mac
EOF
fi
chroot "$root" systemctl enable systemd-networkd systemd-resolved chrony ssh >/dev/null
ln -sf /run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
# mmdebstrap copies the build machine's resolv.conf into the root file system for the
# installation, and systemd-resolved's install script keeps it as a backup. It names the
# build machine's name servers and has no place in the image.
rm -f "$root/etc/.resolv.conf.systemd-resolved.bak"
echo "en_US.UTF-8 UTF-8" > "$root/etc/locale.gen"; chroot "$root" locale-gen >/dev/null
echo 'LANG=en_US.UTF-8' > "$root/etc/default/locale"

# User: password is the user name; sudo without a password. Without ssh keys the password must be
# changed at first login.
chroot "$root" useradd -m -s /bin/bash -G sudo,adm,dialout "$USER_"
echo "$USER_:$USER_" | chroot "$root" chpasswd
echo "$USER_ ALL=(ALL) NOPASSWD:ALL" > "$root/etc/sudoers.d/90-$USER_"; chmod 440 "$root/etc/sudoers.d/90-$USER_"
# /usr/sbin on users' paths in login shells: Debian leaves it off, and the commands for the
# flash and the core are there.
install -m 644 /sd/files/de25-sbin-path.sh "$root/etc/profile.d/de25-sbin-path.sh"
if [ -s /in/authorized_keys ]; then
  install -d -m 700 "$root/home/$USER_/.ssh"
  install -m 600 /in/authorized_keys "$root/home/$USER_/.ssh/authorized_keys"
  chroot "$root" chown -R "$USER_:$USER_" "/home/$USER_/.ssh"
  # Keys were supplied: no password logins over the network. No forced password change, which
  # would block key logins until done at the console.
  mkdir -p "$root/etc/ssh/sshd_config.d"
  echo "PasswordAuthentication no" > "$root/etc/ssh/sshd_config.d/10-keys-only.conf"
else
  chroot "$root" chage -d 0 "$USER_"
fi

# First boot (files/de25-firstboot): new ssh host keys, partition 2 and its file system grown
# to the size of the card, a fixed Ethernet address unless one was given above, and the
# optional hostname and authorized_keys files from the FAT partition.
rm -f "$root"/etc/ssh/ssh_host_*
install -m 755 /sd/files/de25-firstboot "$root/usr/local/sbin/de25-firstboot"
install -m 644 /sd/files/de25-firstboot.service "$root/etc/systemd/system/de25-firstboot.service"
chroot "$root" systemctl enable de25-firstboot.service >/dev/null
: > "$root/etc/machine-id"
rm -rf "$root"/var/lib/apt/lists/* "$root"/var/cache/apt/archives/*.deb
cat > "$root/etc/de25-nano-image" <<EOF
built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
suite: $SUITE
kernel: $KREL
EOF
chroot "$root" dpkg-query -W -f='${Package} ${Version}\n' 'de25-nano-*' >> "$root/etc/de25-nano-image"

# 5. Partition images and the card image. No loop devices: mke2fs -d and mtools.
img=/out/$IMAGE_NAME
root_mb=$((IMAGE_MB - FAT_MB - 1))
rm -f "$work/fat.img" "$work/root.img" "$img"
mkfs.vfat -C -n FIRMWARE "$work/fat.img" $((FAT_MB * 1024)) >/dev/null
# U-Boot and its boot script, from the boot package: the same two files that "de25-flash
# write" puts there. The script sets the device tree name for the menu, writes the flash when
# "de25-flash write" has asked for it, and loads fpga.rbf if it is there. The image does not
# put fpga.rbf there: "de25-fpga select" does, on the board. Without a boot package, U-Boot
# comes from Task B and the script is wrapped here.
if [ "$FABRIC" = yes ]; then
  cp "$root/usr/lib/de25-nano/boot/$BOOT_NAME/u-boot.itb" "$root/usr/lib/de25-nano/boot/$BOOT_NAME/boot.scr" "$work/"
else
  cp /in/u-boot.itb "$work/u-boot.itb"
  mkimage -A arm64 -T script -C none -n "DE25-Nano boot script" -d /in/boot.cmd "$work/boot.scr" >/dev/null
fi
mcopy -i "$work/fat.img" "$work/u-boot.itb" ::u-boot.itb
mcopy -i "$work/fat.img" "$work/boot.scr" ::boot.scr
sed -e "s/@USER@/$USER_/g" -e "s/@HOSTNAME@/$HOSTNAME_/g" /sd/files/firmware-README.txt > "$work/README.txt"
mcopy -i "$work/fat.img" "$work/README.txt" ::README.txt
mke2fs -q -t ext4 -L rootfs -d "$root" "$work/root.img" "${root_mb}M"
truncate -s "${IMAGE_MB}M" "$img"
# Both partitions are marked bootable: U-Boot scans only those, partition 1 for the boot script,
# then partition 2 for the boot menu.
sfdisk -q "$img" <<EOF
label: dos
label-id: $DISK_ID
unit: sectors
start=2048, size=$((FAT_MB * 2048)), type=c, bootable
start=$((2048 + FAT_MB * 2048)), size=$((root_mb * 2048)), type=83, bootable
EOF
dd if="$work/fat.img" of="$img" bs=1M seek=1 conv=notrunc status=none
dd if="$work/root.img" of="$img" bs=1M seek=$((1 + FAT_MB)) conv=notrunc status=none
chown "$OWNER" "$img"
sfdisk -l "$img"
du -sh "$root" | sed 's/^/root filesystem contents: /'
sha256sum "$img"
