# Run on the system in QEMU by sdimage/qemu/inner.sh: "first" after the first boot, "second"
# after a restart. KREL is the kernel release expected.
fail=0; n=0
ok() { n=$((n + 1)); echo "ok $n: $1"; }
bad() { n=$((n + 1)); fail=1; echo "FAILED $n: $1"; [ ! -s /tmp/out ] || sed 's/^/    /' /tmp/out; }
run() { desc=$1; shift; if "$@" > /tmp/out 2>&1; then ok "$desc"; else bad "$desc"; fi; }
no() { desc=$1; shift; if "$@" > /tmp/out 2>&1; then bad "$desc"; else ok "$desc"; fi; }
has() { desc=$1; pat=$2; shift 2; "$@" > /tmp/out 2>&1; if grep -q -- "$pat" /tmp/out; then ok "$desc"; else bad "$desc (wanted: $pat)"; fi; }
lib=/usr/lib/de25-nano; fat=/boot/firmware

run "the kernel is $KREL" test "$(uname -r)" = "$KREL"
state=$(systemctl is-system-running --wait 2>/dev/null)
systemctl --failed --no-legend > /tmp/out 2>&1
if [ "$state" = running ]; then ok "the system is running, no unit failed"; else bad "the system is $state"; fi
run "the host name came from the FAT partition" test "$(hostname)" = qemutest
run "the root file system grew to the card" test "$(df --output=size -BM / | tail -n 1 | tr -dc 0-9)" -gt 1500
no "the first-boot unit is switched off" systemctl is-enabled de25-firstboot.service
run "ssh accepts keys only" grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config.d/10-keys-only.conf
run "dpkg has nothing half installed" sh -c '[ -z "$(dpkg --audit)" ]'
for p in de25-nano-fpga-tools de25-nano-boot-base de25-nano-core-base "linux-image-$KREL"; do
    has "package $p is installed" '^ii' dpkg-query -W -f='${db:Status-Abbrev}\n' "$p"
done
run "the man page is there" man -w de25-fpga
has "de25-hdmi-init.service is enabled and was skipped (no I2C bus 0)" 'enabled' systemctl is-enabled de25-hdmi-init.service
no "Linux has no flash, as on a factory board" test -e /dev/mtd0
has "status: no access to the flash" 'kept from the SoC' sudo de25-fpga status
has "status: the card has the boot package's U-Boot" 'that of de25-nano-boot-base' sudo de25-fpga status
has "status: nothing selected" 'Selected core: none' sudo de25-fpga status
has "status: nothing running" 'Running core: none' sudo de25-fpga status
has "a user's login shell finds de25-fpga, and status needs no root" 'Selected core: none' bash -lc 'de25-fpga status'
has "list shows the base core" '^base .*de25-nano-boot-base' sudo de25-fpga list
no "no core on the FAT partition of a new card" test -e $fat/fpga.rbf

if [ "$1" = first ]; then
    no "select without a yes changes nothing" sh -c 'echo n | sudo de25-fpga select base'
    no "and leaves no request for a flash write" test -e $fat/write-on-boot.rpd
    has "select asks for the flash write that the core needs" 'will be written at the next boot' sudo de25-fpga select --yes base
    run "write-on-boot.rpd is the package's HPS image" cmp $lib/boot/base/hps.rpd $fat/write-on-boot.rpd
    run "the core image is on the FAT partition" cmp $lib/core/base/fpga.rbf $fat/fpga.rbf
    run "the overlay is where the boot menu looks" cmp $lib/core/base/fpga.dtbo /boot/dtbo/fpga.dtbo
    run "the boot menu names the overlay" grep -q 'fdtoverlays .*/boot/dtbo/fpga.dtbo' /boot/extlinux/extlinux.conf
    has "status shows the waiting write" 'waiting for the next boot (de25-nano-boot-base)' sudo de25-fpga status
    has "installing the packages again on the running system works" 'factory contents' \
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall /tmp/de25-nano-fpga-tools_*.deb /tmp/de25-nano-boot-*.deb /tmp/de25-nano-core-*.deb
    run "the core is still selected after that" sh -c "sudo de25-fpga status | grep -q 'Selected core: base'"
    run "the kernel package installs again" sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall /tmp/linux-image-*.deb
    run "the boot menu has an entry for the kernel" grep -q "linux /boot/vmlinuz-$KREL" /boot/extlinux/extlinux.conf
    run "dpkg has nothing half installed afterwards" sh -c '[ -z "$(dpkg --audit)" ]'
    # Put the card back as a new one, for the second boot.
    has "disable" 'No core will be loaded' sudo de25-fpga disable
    sudo rm -f $fat/write-on-boot.rpd $fat/write-on-boot.txt
    no "the boot menu no longer names an overlay" grep -q fdtoverlays /boot/extlinux/extlinux.conf
fi
exit $fail
