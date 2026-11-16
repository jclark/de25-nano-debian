#!/bin/sh
# Run by sdimage/qemu-test.sh, here or in its container: inner.sh TOP IMAGE
set -eu
top=$1; image=$2
w=$(mktemp -d); trap 'kill $qemu 2>/dev/null || true; rm -rf "$w"' EXIT
qemu=
kdeb=$(ls "$top"/out/kernel/linux-image-*_arm64.deb | head -n 1)
krel=$(dpkg-deb -f "$kdeb" Package | sed 's/^linux-image-//')
dpkg-deb -x "$kdeb" $w/k
cp "$image" $w/test.img
truncate -s 2G $w/test.img                       # a card larger than the image
ssh-keygen -q -t ed25519 -N '' -f $w/key
# What a user may put on the FAT partition before the first boot (it starts at 1 MiB).
echo qemutest > $w/hostname
mcopy -i $w/test.img@@1M $w/key.pub ::authorized_keys
mcopy -i $w/test.img@@1M $w/hostname ::hostname

# QEMU's machine has a flash device of its own, which Linux would show as /dev/mtd0. The
# kernel is told to leave its driver out, so that the system looks like a board with the
# factory flash contents, where Linux has no flash.
qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 1024 -display none \
    -kernel $w/k/boot/vmlinuz-"$krel" \
    -append "root=PARTUUID=de250001-02 rw rootwait console=ttyAMA0 initcall_blacklist=physmap_init" \
    -drive if=none,file=$w/test.img,format=raw,id=d -device virtio-blk-pci,drive=d \
    -netdev user,id=n,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=n,romfile= \
    -serial file:$w/console.log &
qemu=$!
g() { ssh -q -i $w/key -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=5 debian@127.0.0.1 "$@"; }
wait_up() {
    i=0
    until g true 2>/dev/null; do
        i=$((i + 1))
        if [ $i -gt 120 ] || ! kill -0 $qemu 2>/dev/null; then
            echo "FAILED: the system did not come up; the end of its console:"; tail -n 40 $w/console.log; exit 1
        fi
        sleep 5
    done
}
echo "# kernel $krel; waiting for the first boot"
wait_up
scp -q -i $w/key -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$top"/out/packages/*.deb "$kdeb" debian@127.0.0.1:/tmp/
status=0
g "KREL=$krel sh -s first" < "$top/sdimage/qemu/checks.sh" || status=1
echo "# restarting"
g "sudo systemctl reboot" || true
sleep 20
wait_up
g "KREL=$krel sh -s second" < "$top/sdimage/qemu/checks.sh" || status=1
g "sudo systemctl poweroff" || true
wait $qemu 2>/dev/null || true
if [ $status -eq 0 ]; then echo "RESULT: all checks passed"; else echo "RESULT: FAILED"; fi
exit $status
