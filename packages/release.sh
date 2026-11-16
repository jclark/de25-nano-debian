#!/bin/sh
# Collect the files of a release in out/release-<version>/, from what is already built.
#
# Usage: packages/release.sh VERSION        (as in the tag: v0.2)
#
#   de25-nano-<version>.img.xz                the card image
#   linux-image-..._arm64.deb                 the kernel package
#   de25-nano-*.deb                           the packages of Task P
#   de25-nano-boot-<name>_<v>.hps.jic         the HPS image for Altera's programmer (flash-jtag.md)
#   config-<release>, Module.symvers-<release>   for building a module for this kernel
#   SHA256SUMS
# NOTES.md, the text of the release, is written by hand; one that is already there is kept.
#
# The files are the ones the image was made from: run it after "make test".
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "packages/release.sh: $*" >&2; exit 1; }
[ $# -eq 1 ] || { sed -n '2,14p' "$0"; exit 2; }
version=$1
case $version in v[0-9]*) ;; *) fail "the version is written as in the tag: v0.2" ;; esac
img=$top/out/sdimage/de25-nano.img
[ -f "$img" ] || fail "no $img"
kdeb=$(ls "$top"/out/kernel/linux-image-*_arm64.deb | head -n 1)
krel=$(dpkg-deb -f "$kdeb" Package | sed 's/^linux-image-//')
boot=$(cat "$top/fpga/BOOT_NAME")
. "$top/packages/VERSIONS"
out=$top/out/release-$version
mkdir -p "$out"
for f in "$out"/*; do
    case ${f##*/} in NOTES.md|'*') ;; *) rm -f "$f" ;; esac
done
xz -T0 -9 -c "$img" > "$out/de25-nano-$version.img.xz"
cp "$kdeb" "$top"/out/packages/de25-nano-*.deb "$out/"
cp "$top/out/packages/de25-nano-boot-${boot}_$BOOT_VERSION.hps.jic" "$out/"
cp "$top/out/kernel/config" "$out/config-$krel"
cp "$top/out/kernel/Module.symvers" "$out/Module.symvers-$krel"
(cd "$out" && sha256sum -- *.xz *.deb *.jic config-* Module.symvers-* > SHA256SUMS)
[ -f "$out/NOTES.md" ] || echo "packages/release.sh: write $out/NOTES.md"
cat "$out/SHA256SUMS"
