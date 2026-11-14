#!/bin/sh
# Runs inside the build container as root. Called by build-image; see that file for the inputs.
# Produces /out/$IMAGE_NAME: MBR; partition 1 FAT (/boot/firmware: U-Boot and its boot script);
# partition 2 ext4 (/, with the kernel and the boot menu in /boot, and the FPGA design, its
# overlay and the first-stage image, not yet enabled, in /usr/lib/de25-nano).
set -eu

: "${SUITE:=trixie}" "${HOSTNAME_:=de25-nano}" "${USER_:=debian}" "${IMAGE_NAME:=de25-nano.img}"
: "${IMAGE_MB:=3072}" "${FAT_MB:=64}" "${DISK_ID:=0xde250001}" "${MAC:=}"
: "${OWNER:=0:0}"

DEB=$(ls /in/linux-image-*_arm64.deb 2>/dev/null | head -1)
[ -n "$DEB" ] || { echo "no linux-image-*_arm64.deb in the input directory" >&2; exit 1; }
KREL=$(dpkg-deb -f "$DEB" Package | sed 's/^linux-image-//')
DTB=intel/socfpga_agilex5_de25_nano.dtb    # under the package's device tree directory; fdtfile in boot.cmd
FABRIC=no
if [ -f /in/fpga.rbf ] || [ -f /in/fpga.dtbo ]; then
  [ -f /in/fpga.rbf ] && [ -f /in/fpga.dtbo ] && [ -f /in/hps-first.rpd ] || { echo "fpga.rbf, fpga.dtbo and hps-first.rpd go together" >&2; exit 1; }
  FABRIC=yes
fi
PARTUUID_ROOT=$(printf '%08x-02' "$DISK_ID")
PARTUUID_FAT=$(printf '%08x-01' "$DISK_ID")
echo "kernel release $KREL, FPGA design in the image: $FABRIC, root PARTUUID=$PARTUUID_ROOT"

work=/work; root=$work/root
mkdir -p "$work"; find "$work" -mindepth 1 -maxdepth 1 -exec rm -rf {} +; mkdir -p "$root"

# 1. Debian root filesystem from the archive.
mmdebstrap --architectures=arm64 --variant=important \
  --include=systemd-sysv,systemd-resolved,chrony,udev,kmod,openssh-server,sudo,ca-certificates,locales,iproute2,iputils-ping,ethtool,pciutils,usbutils,less,vim-tiny,curl,fdisk,cloud-guest-utils,e2fsprogs,dosfstools,dbus,libnss-systemd,i2c-tools,linuxptp,mtd-utils,u-boot-menu \
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
# The FPGA design and its overlay are kept out of the way of the boot, with the first-stage
# image the design belongs to (hps-first.rpd). "de25-fpga enable" on the board puts them where
# the boot uses them, and has the flash written first on a board that needs it.
install -m 755 /sd/files/de25-fpga "$root/usr/local/sbin/de25-fpga"
if [ "$FABRIC" = yes ]; then
  install -d "$root/usr/lib/de25-nano"
  install -m 644 /in/fpga.rbf /in/fpga.dtbo /in/hps-first.rpd "$root/usr/lib/de25-nano/"
fi

# 3. The kernel package: kernel, modules, device trees.
cp "$DEB" "$root/tmp/kernel.deb"
chroot "$root" dpkg -i /tmp/kernel.deb
rm -f "$root/tmp/kernel.deb"
chroot "$root" u-boot-update
[ -f "$root/usr/lib/linux-image-$KREL/$DTB" ] || { echo "the kernel package has no $DTB" >&2; exit 1; }
menu=$root/boot/extlinux/extlinux.conf
grep -q "fdtdir /usr/lib/linux-image-$KREL/" "$menu" || { echo "the boot menu has no fdtdir line for $KREL" >&2; exit 1; }
cat "$menu"

# 3a. Files for what the FPGA design adds. They do nothing without it: the udev rule waits for
# the fan controller, and the HDMI unit has a condition on the I2C bus that the overlay enables.
install -m 644 /sd/files/60-de25-fan.rules "$root/etc/udev/rules.d/60-de25-fan.rules"
install -m 755 /sd/files/de25-fan-curve "$root/usr/local/sbin/de25-fan-curve"
install -m 644 /sd/files/de25-fan.default "$root/etc/default/de25-fan"
install -m 755 /sd/files/de25-hdmi-init "$root/usr/local/sbin/de25-hdmi-init"
install -m 644 /sd/files/de25-hdmi-init.service "$root/etc/systemd/system/de25-hdmi-init.service"
chroot "$root" systemctl enable de25-hdmi-init.service >/dev/null

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
echo "en_US.UTF-8 UTF-8" > "$root/etc/locale.gen"; chroot "$root" locale-gen >/dev/null
echo 'LANG=en_US.UTF-8' > "$root/etc/default/locale"

# User: password is the user name; sudo without a password. Without ssh keys the password must be
# changed at first login.
chroot "$root" useradd -m -s /bin/bash -G sudo,adm,dialout "$USER_"
echo "$USER_:$USER_" | chroot "$root" chpasswd
echo "$USER_ ALL=(ALL) NOPASSWD:ALL" > "$root/etc/sudoers.d/90-$USER_"; chmod 440 "$root/etc/sudoers.d/90-$USER_"
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
FPGA design in /usr/lib/de25-nano: $FABRIC
EOF

# 5. Partition images and the card image. No loop devices: mke2fs -d and mtools.
img=/out/$IMAGE_NAME
root_mb=$((IMAGE_MB - FAT_MB - 1))
rm -f "$work/fat.img" "$work/root.img" "$img"
mkfs.vfat -C -n FIRMWARE "$work/fat.img" $((FAT_MB * 1024)) >/dev/null
mcopy -i "$work/fat.img" /in/u-boot.itb ::u-boot.itb
# The boot script: sets the device tree name for the menu, writes the flash when
# "de25-fpga enable" has asked for it, and loads fpga.rbf if it is there. The image does not
# put fpga.rbf there: "de25-fpga enable" does, on the board.
mkimage -A arm64 -T script -C none -n "DE25-Nano boot script" -d /sd/boot.cmd "$work/boot.scr" >/dev/null
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
