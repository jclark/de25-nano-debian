#!/bin/sh
# Test de25-fpga off the board, against a made-up card and a file standing in for the flash
# (DE25_TEST_ROOT, see de25-fpga). Usage: packages/fpga-tools/test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export DE25_TEST_ROOT=$t
fpga() { sh "$here/de25-fpga" "$@"; }
n=0
ok() { n=$((n + 1)); echo "ok $n: $1"; }
bad() { echo "FAILED: $1" >&2; exit 1; }
expect() { # expect PATTERN DESCRIPTION -- COMMAND...
    pat=$1; what=$2; shift 3
    out=$("$@" 2>&1) || true
    echo "$out" | grep -q -- "$pat" || { echo "$out" >&2; bad "$what (wanted: $pat)"; }
    ok "$what"
}
refuse() { # refuse DESCRIPTION -- COMMAND...: it must fail
    what=$1; shift 2
    if "$@" >/dev/null 2>&1; then bad "$what"; fi
    ok "$what"
}
blob() { head -c "$2" /dev/urandom > "$1"; }
lib=$t/usr/lib/de25-nano; fat=$t/boot/firmware; dt=$t/proc/device-tree/chosen
mkboot() { d=$lib/boot/$1; mkdir -p "$d"; blob "$d/hps.rpd" 4096; blob "$d/u-boot.itb" 512; blob "$d/boot.scr" 128; }
mkcore() { d=$lib/core/$1; mkdir -p "$d"; blob "$d/fpga.rbf" 2048; blob "$d/fpga.dtbo" 256; echo "$2" > "$d/boot"; }
running() { mkdir -p "$dt"; printf '%s\0' "$1" > "$dt/de25-nano,core"; printf '%s\0' "$2" > "$dt/de25-nano,boot"; }
not_running() { rm -rf "$t/proc/device-tree"; }
r=0
reboot_() { r=$((r + 1)); echo "boot-$r" > "$t/proc/sys/kernel/random/boot_id"; rm -rf "$t/run"; }
selected() { [ -f "$fat/fpga.rbf" ] && cmp -s "$lib/core/$1/fpga.rbf" "$fat/fpga.rbf" && cmp -s "$lib/core/$1/fpga.dtbo" "$t/boot/dtbo/fpga.dtbo" && grep -q "^core=$1\$" "$fat/fpga-core.txt"; }
flash_is() { cmp -s -n 4096 "$t/dev/mtd0" "$lib/boot/$1/hps.rpd"; }
crc() { gzip -1 -c "$1" | tail -c 8 | head -c 4 | od -An -tx4 | tr -d ' \n'; }
mkdir -p "$fat" "$t/boot/dtbo" "$t/dev" "$t/proc/sys/kernel/random"
reboot_
mkboot base; mkcore base base; mkcore tic base; mkboot other; mkcore odd other
blob "$fat/u-boot.itb" 512; blob "$fat/boot.scr" 128     # as an older image left them

echo "# A factory board: no /dev/mtd0"
expect "Selected core: none" "status with nothing selected" -- fpga status
expect "Flash: factory contents" "status: the flash on a factory board" -- fpga status
expect "base .*for de25-nano-boot-base" "list" -- fpga list
refuse "select without a yes changes nothing" -- sh -c "echo n | sh '$here/de25-fpga' select base"
[ ! -e "$fat/fpga.rbf" ] && [ ! -e "$fat/write-on-boot.rpd" ] || bad "a declined select left files"
ok "a declined select leaves no files"
expect "will be reflashed at the next boot" "select has the flash written and puts the core in place" -- fpga select --yes base
cmp -s "$lib/boot/base/hps.rpd" "$fat/write-on-boot.rpd" || bad "write-on-boot.rpd"
grep -q "^flash_new_crc=$(crc "$lib/boot/base/hps.rpd")\$" "$fat/write-on-boot.txt" || bad "crc32 in write-on-boot.txt"
cmp -s "$lib/boot/base/u-boot.itb" "$fat/u-boot.itb" && cmp -s "$lib/boot/base/boot.scr" "$fat/boot.scr" || bad "U-Boot not put on the card"
[ -f "$fat/u-boot-previous.itb" ] || bad "the previous u-boot.itb was not kept"
selected base || bad "base not selected"
ok "the request, U-Boot and the core are all on the card"
expect "Reflash: at the next boot (de25-nano-boot-base)" "status shows the waiting write" -- fpga status
expect "will be loaded at the next boot" "status before the reboot" -- fpga status
expect "will still be reflashed at that boot" "another core for the same HPS image is selected without more" -- fpga select tic
selected tic || bad "tic not selected"
cmp -s "$lib/boot/base/hps.rpd" "$fat/write-on-boot.rpd" || bad "the waiting write was disturbed"
fpga select base >/dev/null

echo "# After U-Boot wrote the flash and the power cycle: the core runs"
rm "$fat/write-on-boot.rpd" "$fat/write-on-boot.txt"; blob "$fat/saved-0badcafe.rpd" 64
head -c 16777216 /dev/zero > "$t/dev/mtd0"; dd if="$lib/boot/base/hps.rpd" of="$t/dev/mtd0" conv=notrunc status=none
reboot_; running base base
expect "Running core: base" "status with the core running" -- fpga status
expect "Flash: de25-nano-boot-base, as installed" "status: the flash" -- fpga status
expect "U-Boot on the SD card: de25-nano-boot-base" "status: U-Boot on the card" -- fpga status
expect "base .*selected, running" "list" -- fpga list
expect "Nothing to do" "flash-write when flash and card are current" -- fpga flash-write base
refuse "flash-write needs a name when two boot packages are installed" -- fpga flash-write --yes
expect "does not need reflashing" "select another core for the same HPS image: no flash write" -- fpga select tic
selected tic || bad "tic not put in place"
flash_is base || bad "the flash was touched"

echo "# Upgrades"
blob "$lib/core/tic/fpga.rbf" 2048
expect "the new \"tic\" FPGA core" "an upgrade of the selected core is put in place" -- fpga hook core-configure tic
selected tic || bad "upgraded tic not put in place"
blob "$lib/core/base/fpga.rbf" 2048
[ -z "$(fpga hook core-configure base)" ] || bad "an upgrade of an unselected core did something"
ok "an upgrade of an unselected core does nothing"
blob "$lib/boot/base/u-boot.itb" 512
expect "has been updated" "a boot upgrade with the same HPS image renews U-Boot on the card" -- fpga hook boot
cmp -s "$lib/boot/base/u-boot.itb" "$fat/u-boot.itb" || bad "u-boot.itb not renewed"
blob "$lib/boot/base/hps.rpd" 4096; blob "$lib/boot/base/u-boot.itb" 512; cp "$fat/u-boot.itb" "$t/itb-before"
expect "takes effect when the board is reflashed" "a boot upgrade with a new HPS image leaves the card alone" -- fpga hook boot
cmp -s "$t/itb-before" "$fat/u-boot.itb" || bad "the hook changed u-boot.itb although the flash differs"
expect "an earlier build than the one installed" "status: an older build of the same boot package" -- fpga status
expect "does not need reflashing" "a core still fits an older build of its HPS image" -- fpga select base
flash_is base && bad "select wrote the flash although the core fits"
expect "has been reflashed" "flash-write brings the flash to the new build" -- fpga flash-write --yes base
flash_is base || bad "the flash was not written"
cmp -s "$lib/boot/base/u-boot.itb" "$fat/u-boot.itb" || bad "u-boot.itb not renewed with the flash"
selected base || bad "flash-write dropped a core that fits"
ok "flash-write leaves a selected core that fits"

echo "# A core for other SoC settings"
expect "has been reflashed" "select of a core for another boot package writes the flash" -- fpga select --yes odd
flash_is other || bad "the flash does not hold the other HPS image"
selected odd || bad "odd not selected"
cmp -s "$lib/boot/other/u-boot.itb" "$fat/u-boot.itb" || bad "the other U-Boot is not on the card"
expect "needs to be reflashed" "before the power cycle, the running core is no proof of what the flash holds" -- sh -c "echo n | sh '$here/de25-fpga' select base"
selected odd || bad "a declined select changed the selection"
reboot_; running odd other
expect "no core is selected now" "flash-write of an HPS image the selected core does not load on deselects it" -- fpga flash-write --yes base
[ ! -e "$fat/fpga.rbf" ] && [ ! -e "$t/boot/dtbo/fpga.dtbo" ] || bad "a core that does not fit was left selected"
flash_is base || bad "flash-write base"
expect "base tic" "and names the cores that do" -- sh -c "sh '$here/de25-fpga' flash-write --yes other >/dev/null; sh '$here/de25-fpga' select --yes odd >/dev/null; sh '$here/de25-fpga' flash-write --yes base"

echo "# A flash write that fails"
reboot_; not_running; fpga disable >/dev/null
dd if="$lib/boot/other/hps.rpd" of="$t/dev/mtd0" conv=notrunc status=none
fpga select odd >/dev/null; selected odd || bad "set-up for the failing write"
chmod a-w "$t/dev/mtd0"
refuse "select fails when the flash cannot be written" -- fpga select --yes base
chmod u+w "$t/dev/mtd0"
[ ! -e "$fat/fpga.rbf" ] || bad "a failed flash write left a core selected"
ok "and leaves no core selected"
flash_is other || bad "the flash changed"

echo "# A request that will not be carried out, and one that is withdrawn"
reboot_
cp "$lib/boot/base/hps.rpd" "$fat/write-on-boot.rpd"; printf 'flash_new_crc=0\nflash_new_boot=base\n' > "$fat/write-on-boot.txt"
expect "needs to be reflashed" "a request on a board that will not act on it is no proof" -- sh -c "echo n | sh '$here/de25-fpga' select base"
[ ! -e "$fat/fpga.rbf" ] || bad "select trusted a stale request"
mv "$t/dev/mtd0" "$t/mtd0.aside"
fpga select --yes base >/dev/null; [ -f "$fat/write-on-boot.rpd" ] || bad "set-up for disable"
expect "will not be reflashed" "disable withdraws a waiting reflash" -- fpga disable
[ ! -e "$fat/write-on-boot.rpd" ] && [ ! -e "$fat/write-on-boot.txt" ] || bad "disable left the request"
mv "$t/mtd0.aside" "$t/dev/mtd0"
: > "$lib/core/tic/boot"
refuse "a core that names no boot package is not selected" -- fpga select --yes tic
echo base > "$lib/core/tic/boot"

echo "# A refused core"
reboot_; not_running
dd if="$lib/boot/base/hps.rpd" of="$t/dev/mtd0" conv=notrunc status=none
fpga select base >/dev/null; reboot_
expect "selected but was not loaded" "status after a core was not loaded" -- fpga status
expect "No FPGA core will be loaded" "disable" -- fpga disable
[ ! -e "$fat/fpga.rbf" ] && [ ! -e "$t/boot/dtbo/fpga.dtbo" ] && [ ! -e "$fat/fpga-core.txt" ] || bad "disable left files"
expect "does not need reflashing" "nothing running: select by reading the flash" -- fpga select base
running base base
expect "was the selected FPGA core" "removing the selected core's package disables it" -- fpga hook core-remove base
[ ! -e "$fat/fpga.rbf" ] || bad "remove left fpga.rbf"

echo "# A card set up by hand, as before release 0.2: a core with no name beside it"
blob "$fat/fpga.rbf" 2048; blob "$t/boot/dtbo/fpga.dtbo" 256; rm -f "$fat/fpga-core.txt"
not_running; mkdir -p "$dt/framebuffer@bf000000"
blob "$t/v6.rpd" 4096; dd if="$t/v6.rpd" of="$t/dev/mtd0" conv=notrunc status=none
expect "Selected core: unknown" "status: a selected core without a name" -- fpga status
expect "Running core: unknown" "status: a running core without a name" -- fpga status
expect "not from an installed boot package" "status: a flash with other contents" -- fpga status
blob "$fat/write-on-boot.rpd" 64; rm -f "$fat/write-on-boot.txt"
expect "a stale request" "status: a request file without its text file" -- fpga status
expect "has been reflashed" "select replaces the core and writes the flash, in one step" -- fpga select --yes base
selected base || bad "base not selected"
flash_is base || bad "the flash was not written"
[ ! -e "$fat/write-on-boot.rpd" ] || bad "a stale request was left"
blob "$fat/fpga.rbf" 2048; rm -f "$fat/fpga-core.txt"; dd if="$t/v6.rpd" of="$t/dev/mtd0" conv=notrunc status=none
expect "no core is selected now" "flash-write does not leave a core it cannot vouch for" -- fpga flash-write --yes base
[ ! -e "$fat/fpga.rbf" ] || bad "the unknown core was left selected"
rmdir "$dt/framebuffer@bf000000"

echo "# Restore"
refuse "flash-restore refuses a file that is not the whole flash" -- fpga flash-restore --yes
head -c 16777216 /dev/urandom > "$t/factory"
rm "$fat/saved-0badcafe.rpd"; cp "$t/factory" "$fat/saved-0badcafe.rpd"
refuse "flash-restore refuses a file that is not what its name says" -- fpga flash-restore --yes
mv "$fat/saved-0badcafe.rpd" "$fat/saved-$(crc "$t/factory").rpd"
fpga select base >/dev/null
expect "has been reflashed" "flash-restore" -- fpga flash-restore --yes
cmp -s "$t/factory" "$t/dev/mtd0" || bad "flash-restore did not write the flash"
[ ! -e "$fat/fpga.rbf" ] || bad "flash-restore left a core selected"
echo "all $n tests passed"
