#!/bin/sh
# Runs inside the build container as root. Called by build-image; see that file for the inputs.
# Produces /out/$IMAGE_NAME: MBR; partition 1 FAT (/boot/firmware: U-Boot, its boot script and, for
# stage 2, the FPGA design); partition 2 ext4 (/, with the kernel and the boot menu in /boot).
set -eu

: "${SUITE:=trixie}" "${HOSTNAME_:=de25-nano}" "${USER_:=debian}" "${IMAGE_NAME:=de25-nano.img}"
: "${IMAGE_MB:=3072}" "${FAT_MB:=64}" "${DISK_ID:=0xde250001}" "${MAC:=}"
: "${OWNER:=0:0}"

KREL=$(tar tzf /in/modules.tar.gz | sed -n 's|^usr/lib/modules/\([^/]*\)/$|\1|p' | head -1)
[ -n "$KREL" ] || { echo "cannot find the kernel release in modules.tar.gz" >&2; exit 1; }
DTB=socfpga_agilex5_de25_nano.dtb      # the name U-Boot looks for: fdtfile in boot.cmd
[ -f "/in/dtbs/$DTB" ] || { echo "no /in/dtbs/$DTB" >&2; exit 1; }
FABRIC=no
if [ -f /in/fpga.rbf ] || [ -f /in/fpga.dtbo ]; then
  [ -f /in/fpga.rbf ] && [ -f /in/fpga.dtbo ] || { echo "fpga.rbf and fpga.dtbo go together" >&2; exit 1; }
  FABRIC=yes
fi
PARTUUID_ROOT=$(printf '%08x-02' "$DISK_ID")
PARTUUID_FAT=$(printf '%08x-01' "$DISK_ID")
echo "kernel release $KREL, FPGA design on the card: $FABRIC, root PARTUUID=$PARTUUID_ROOT"

work=/work; root=$work/root
mkdir -p "$work"; find "$work" -mindepth 1 -maxdepth 1 -exec rm -rf {} +; mkdir -p "$root"

# 1. Debian root filesystem from the archive.
mmdebstrap --architectures=arm64 --variant=important \
  --include=systemd-sysv,systemd-resolved,systemd-timesyncd,udev,kmod,openssh-server,sudo,ca-certificates,locales,iproute2,iputils-ping,ethtool,pciutils,usbutils,less,vim-tiny,curl,fdisk,cloud-guest-utils,e2fsprogs,dosfstools,dbus,libnss-systemd,i2c-tools,linuxptp \
  "$SUITE" "$root"

# 2. Kernel: image, device trees, modules. (A kernel .deb would replace this step.)
mkdir -p "$root/boot/dtbs/$KREL" "$root/boot/extlinux" "$root/boot/firmware" "$root/boot/dtbo"
cp /in/Image "$root/boot/vmlinuz-$KREL"
cp /in/dtbs/*.dtb "$root/boot/dtbs/$KREL/"
[ ! -f /in/config ] || cp /in/config "$root/boot/config-$KREL"
tar xzf /in/modules.tar.gz -C "$root" --no-same-owner
chroot "$root" depmod "$KREL"

# 3. Boot menu, read by U-Boot from this partition after it has run boot.scr on partition 1.
# fdtdir: U-Boot loads <fdtdir>/<fdtfile>, and boot.scr sets fdtfile to the board's tree, so each
# kernel keeps its own device tree. fdtoverlays: the overlay for the FPGA design, applied on top.
# console=tty0 is the HDMI console when the design is loaded; the last console named, the
# serial one, is where /dev/console goes.
if [ "$FABRIC" = yes ]; then
  cp /in/fpga.dtbo "$root/boot/dtbo/fpga.dtbo"
  overlay_line="    fdtoverlays /boot/dtbo/fpga.dtbo"
else
  overlay_line="    #fdtoverlays /boot/dtbo/fpga.dtbo"
fi
cat > "$root/boot/extlinux/extlinux.conf" <<EOF
# U-Boot boot menu for the DE25-Nano. Paths are on this partition.
# The fdtoverlays line is for the FPGA design in /boot/firmware/fpga.rbf: leave it commented
# out ("#") when there is no design on the card.
default linux
menu title DE25-Nano
prompt 0
timeout 30

label linux
    menu label Debian, Linux $KREL
    linux /boot/vmlinuz-$KREL
    fdtdir /boot/dtbs/$KREL/
$overlay_line
    append root=PARTUUID=$PARTUUID_ROOT rw rootwait console=tty0 console=ttyS0,115200 earlycon
EOF

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
cat > "$root/etc/fstab" <<EOF
PARTUUID=$PARTUUID_ROOT  /               ext4  defaults,noatime  0 1
PARTUUID=$PARTUUID_FAT  /boot/firmware  vfat  defaults,noatime  0 2
EOF
mkdir -p "$root/etc/systemd/network"
cat > "$root/etc/systemd/network/20-wired.network" <<EOF
[Match]
Type=ether

[Network]
DHCP=yes
EOF
if [ -n "$MAC" ]; then
  # The board has no stored MAC address and U-Boot invents one at each boot.
  cat > "$root/etc/systemd/network/10-emac0.link" <<EOF
[Match]
Path=platform-10810000.ethernet

[Link]
MACAddress=$MAC
NamePolicy=kernel
EOF
fi
chroot "$root" systemctl enable systemd-networkd systemd-resolved systemd-timesyncd ssh >/dev/null
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

# First boot: new ssh host keys, grow partition 2 and its filesystem to the size of the card.
rm -f "$root"/etc/ssh/ssh_host_*
cat > "$root/usr/local/sbin/de25-firstboot" <<'EOF'
#!/bin/sh
set -u
ssh-keygen -A
rootdev=$(findmnt -n -o SOURCE /)            # /dev/mmcblk0p2
disk=/dev/$(lsblk -n -o PKNAME "$rootdev")    # /dev/mmcblk0
growpart "$disk" 2 || true
resize2fs "$rootdev" || true
systemctl disable de25-firstboot.service
EOF
chmod 755 "$root/usr/local/sbin/de25-firstboot"
cat > "$root/etc/systemd/system/de25-firstboot.service" <<EOF
[Unit]
Description=DE25-Nano first boot: ssh host keys, grow the root filesystem
Before=ssh.service
ConditionPathExists=/usr/local/sbin/de25-firstboot

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/de25-firstboot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
chroot "$root" systemctl enable de25-firstboot.service >/dev/null
: > "$root/etc/machine-id"
rm -rf "$root"/var/lib/apt/lists/* "$root"/var/cache/apt/archives/*.deb
cat > "$root/etc/de25-nano-image" <<EOF
built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
suite: $SUITE
kernel: $KREL
FPGA design on the card: $FABRIC
EOF

# 5. Partition images and the card image. No loop devices: mke2fs -d and mtools.
img=/out/$IMAGE_NAME
root_mb=$((IMAGE_MB - FAT_MB - 1))
rm -f "$work/fat.img" "$work/root.img" "$img"
mkfs.vfat -C -n FIRMWARE "$work/fat.img" $((FAT_MB * 1024)) >/dev/null
mcopy -i "$work/fat.img" /in/u-boot.itb ::u-boot.itb
# The boot script: sets the device tree name for the menu and loads fpga.rbf if it is there.
mkimage -A arm64 -T script -C none -n "DE25-Nano boot script" -d /sd/boot.cmd "$work/boot.scr" >/dev/null
mcopy -i "$work/fat.img" "$work/boot.scr" ::boot.scr
[ "$FABRIC" = no ] || mcopy -i "$work/fat.img" /in/fpga.rbf ::fpga.rbf
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
