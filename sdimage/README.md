# Task I: SD card image

```mermaid
flowchart LR
  deb(["Debian archive"]) --> m["Build the image"]
  s(["build-image, boot.cmd, files/"]) --> m
  itb[/"u-boot.itb<br/>from Task B"/] --> m
  k[/"linux-image-...arm64.deb<br/>from Task K"/] --> m
  f[/"fpga.rbf, fpga.dtbo<br/>from Task F"/] -.-> m
  m --> img[/"de25-nano.img"/]
```

## What it produces

`out/sdimage/de25-nano.img`: a complete card image, 3 GB (about 115 MB compressed with `xz`),
to be written to a microSD card ([install-card.md](../install-card.md)).

It is one image for every board. U-Boot tries to load the FPGA design at each boot. A board
whose flash has been written for stage 2 accepts it. A board with the factory flash contents
refuses it and boots without the design and without its device tree overlay, which is stage 1.
So the same card works before and after the flash is written.

When Task F has not been built, the script makes `out/sdimage/de25-nano-nofpga.img` instead:
the same image without the FPGA design and its overlay. It behaves as stage 1 on any board.

| Partition | Contents |
|---|---|
| 1, FAT, 64 MB, mounted at `/boot/firmware` | `u-boot.itb`; `boot.scr`, the U-Boot script; `fpga.rbf`, the FPGA design; `README.txt` |
| 2, ext4, the rest, `/` | Debian 13 with the kernel package from Task K installed; the boot menu `/boot/extlinux/extlinux.conf`; `/boot/dtbo/fpga.dtbo`, the overlay for the FPGA design |

Both partitions are marked bootable, because U-Boot scans only those: partition 1 for the
script, then partition 2 for the menu.

This task owns the layout of the card, so the pieces that make it boot are here:

- **`boot.cmd`**, wrapped into `boot.scr` during the build. It gives U-Boot what its own
  configuration for this board lacks: the name of the device tree file inside a kernel
  package's directory, and the address and size limit for unpacking a compressed kernel. It
  loads `fpga.rbf`, and only when that has succeeded does it set the address overlays are
  loaded to; without that address U-Boot skips the overlay named in the boot menu.
- **The boot menu** is written by Debian's `u-boot-menu` package (`u-boot-update`), not by
  this task. It makes an entry for every installed kernel, newest first, each with that
  kernel's own device tree directory, and it names every overlay it finds in `/boot/dtbo`. It
  runs again whenever a kernel package is installed or removed. Its settings are in
  `/etc/default/u-boot` (from `files/u-boot.default`): the kernel command line and the menu's
  timeout.
- **`files/`** also has what the FPGA design needs in Linux: the udev rule, script and settings
  file for the fan curve, and the script and unit that set up the HDMI transmitter. Without
  the FPGA design they do nothing.

### First boot

Nothing in the image is specific to a person or a board. The first boot of a card
(`files/de25-firstboot`, run once, before the network comes up) does the rest:

- makes new ssh host keys;
- grows partition 2 to fill the card;
- makes up an Ethernet address and keeps it in `/etc/systemd/network/10-emac0.link`. The
  board stores none, and U-Boot would otherwise invent a new one at every boot. The interface
  keeps Debian's usual name for it, `end0`;
- reads two optional files that the user put on the FAT partition beforehand, from any
  computer:

| File on the FAT partition | Effect |
|---|---|
| `hostname` | One line: the board's host name. Without it the name is `de25-nano`. |
| `authorized_keys` | ssh public keys for the user. With it, ssh accepts keys only. |

The user is `debian`, with `sudo` without a password. Without an `authorized_keys` file the
password is `debian` and has to be changed at the first login. The network uses DHCP.

## What it needs first

- Task B: `out/u-boot/u-boot.itb`.
- Task K: `out/kernel/linux-image-*_arm64.deb`.
- Task F, for the complete image: `out/fpga/fpga.rbf` and `out/fpga/fpga.dtbo`.

## Tools to download

Docker. On a host that is not arm64, qemu-user with binfmt for aarch64 (Debian and Ubuntu:
`qemu-user-static` or `qemu-user-binfmt`): the build runs arm64 programs while it puts the
root file system together. Check with `ls /proc/sys/fs/binfmt_misc/ | grep aarch64`.

The build runs in a privileged container, which `mmdebstrap` needs to mount `/proc` and
`/dev` inside the new root file system.

## Source

Debian packages from the archive, fetched by `mmdebstrap`, among them `u-boot-menu`. From
this directory: `build.sh` (collects the other tasks' outputs), `build-image` and
`mkimage-inner.sh` (make the image), `boot.cmd`, `files/`.

## Commands

```
sdimage/build.sh
```

Five to ten minutes. It ends by printing the boot menu that `u-boot-update` wrote, the
partition table (both partitions with `*` in the Boot column) and the image's checksum.

The same things that the first boot sets up can be fixed in the image when it is built, for
an image meant for one board; the top of `build.sh` lists the settings:

```
SSH_KEYS=~/.ssh/id_ed25519.pub HOSTNAME_=myboard MAC=02:de:25:00:00:01 sdimage/build.sh
```

Any Ethernet address with the second hex digit 2, 6, a or e is a valid locally administered
one.

## Changing the card later

To try a changed FPGA design, replace the two files and reboot. No flash write is needed as
long as the first stage is unchanged:

```
sudo cp fpga.rbf /boot/firmware/fpga.rbf
sudo cp fpga.dtbo /boot/dtbo/fpga.dtbo
sudo reboot
```

To add the FPGA design to a card made from `de25-nano-nofpga.img`, do the same and run
`sudo u-boot-update` before the reboot, so that the boot menu names the overlay.

To change the kernel, install a newer package from Task K with `sudo dpkg -i`. The boot menu
is rewritten and the newest kernel becomes its default; the old one stays as the second
entry until its package is removed.
