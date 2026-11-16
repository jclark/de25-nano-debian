#!/bin/sh
# Build everything: the card image and the packages, from source. See build.md.
#
# Usage: ./build.sh [--no-fpga] [--test]
#   --no-fpga   do not run Task F: no Quartus needed. Unless Task F was built before, the
#               result is the image for stage 1, out/sdimage/de25-nano-nofpga.img, and only
#               the tools package.
#   --test      afterwards, boot the image in QEMU and check it (sdimage/qemu-test.sh)
#
# Output: out/sdimage/de25-nano.img                  the card image
#         out/kernel/linux-image-*_arm64.deb         the kernel package
#         out/packages/de25-nano-*.deb               the other packages
#
# Tasks B (U-Boot), K (kernel) and F (FPGA design) run at the same time; then Task P
# (packages) and Task I (image). Each task's output goes to a file in work/logs/, and a line
# is printed here as each starts and finishes. A task that has been built before does only
# what is left to do. The first run with Task F pulls the Quartus image (17.5 GiB).
#
# Needs: what build.md lists under "What you need".
set -eu
top=$(cd "$(dirname "$0")" && pwd)
fpga=yes; test=no
for a in "$@"; do
    case $a in
    --no-fpga) fpga=no ;;
    --test) test=yes ;;
    *) sed -n '2,19p' "$0"; exit 2 ;;
    esac
done
logs=$top/work/logs
mkdir -p "$logs"
now() { date +%H:%M:%S; }
run() {     # run LETTER SCRIPT: one task, its output in a log; 0 if it succeeded
    echo "$(now) Task $1 started: $2 (log: work/logs/$1.log)"
    if "$top/$2" > "$logs/$1.log" 2>&1; then
        echo "$(now) Task $1 finished"
    else
        echo "$(now) Task $1 FAILED. The end of work/logs/$1.log:"
        tail -n 25 "$logs/$1.log" | sed 's/^/    /'
        return 1
    fi
}

run B u-boot/build.sh & b=$!
run K kernel/build.sh & k=$!
f=
if [ $fpga = yes ]; then run F fpga/build.sh & f=$!; fi
ok=yes
wait $b || ok=no
wait $k || ok=no
if [ -n "$f" ] && ! wait $f; then
    # Task F needs Task B's SPL for its last step only. If it got there first, it stopped
    # with a message; run again, it carries on from the compiled design.
    if [ $ok = yes ] && grep -q 'build Task B first' "$logs/F.log"; then
        run F fpga/build.sh || ok=no
    else
        ok=no
    fi
fi
[ $ok = yes ] || { echo "$(now) Stopped: a task failed." >&2; exit 1; }

run P packages/build.sh
run I sdimage/build.sh
if [ $test = yes ]; then run T sdimage/qemu-test.sh; fi
echo "$(now) Done:"
ls -l "$top"/out/sdimage/*.img "$top"/out/kernel/*.deb "$top"/out/packages/*.deb
