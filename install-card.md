# Write the card, first boot

Needs: the image from Task I ([sdimage/README.md](sdimage/README.md)), a microSD card of 4 GB or
more, the board's USB-C cable.

The same image serves both stages: stage 1, with the factory flash contents, and stage 2,
after the flash has been written from the board with `sudo de25-fpga enable`, a reboot and a
power cycle ([install-flash.md](install-flash.md)).

## Write the card

Find the card's device name (`lsblk`), make sure nothing on it is mounted, then:

```
sudo dd if=out/sdimage/de25-nano.img of=/dev/sdX bs=4M conv=fsync status=progress
```

This overwrites the whole card. Keep the card that came with the board as it is: it is the
way back to the vendor's system.

## Before the first boot, optionally

The card's first partition is FAT and can be opened on any computer. Two files put there are
read once, at the first boot:

| File | Contents |
|---|---|
| `hostname` | One line: the name for the board. Without it the name is `de25-nano`. |
| `authorized_keys` | Your ssh public keys, one a line. With it, ssh accepts keys only. |

`README.txt` on that partition says the same.

## Serial console

The board's USB-C socket gives a USB hub with two serial ports and the JTAG cable. The
SoC's console is the port that Linux on the PC lists as

```
/dev/serial/by-id/usb-TERASIC_DE25-Nano_<serial number>-if02-port0
```

at 115200 baud, 8 bits, no parity, for example `picocom -b 115200 <that path>`.

## First boot

Put the card in, connect Ethernet, power the board. On the console, in this order:

1. `U-Boot SPL 2025.01-...`: the first-stage loader from the flash. It sets up the memory and
   loads `u-boot.itb` from the card.
2. `U-Boot 2025.01-gd0f8813fd6bf-dirty (<date of your build>)`, then a five second
   countdown. A key stops it at the prompt `SOCFPGA_AGILEX5 #`; `boot` carries on.
3. `Found U-Boot script /boot.scr`, then
   `No fpga.rbf on the card: booting without the FPGA design`; or, once the FPGA design has
   been enabled in stage 2, `FPGA reconfiguration OK!`. Then `SCRIPT FAILED: continuing...`,
   which is what U-Boot prints when any script returns, not a fault.
4. `Found /boot/extlinux/extlinux.conf`, then the kernel and the device tree are fetched,
   and, with the FPGA design enabled, the overlay. `Starting kernel ...`.
5. Debian's login prompt. The first boot takes a little longer: it makes the ssh host keys,
   grows the root partition to the size of the card, and makes up the board's Ethernet
   address.

Log in as `debian`: with your ssh key if you gave an `authorized_keys` file, or with the
password `debian`, which then has to be changed at once. `sudo` asks for no password.

If the SPL says `mmc init failed with error: -95`, the card is not seated; it can pop out when
cables are handled.

## Check

```
uname -r                        # the kernel built in Task K
ip -br addr show end0           # an address from DHCP
ls /sys/class/ptp/              # ptp0: the Ethernet MAC's clock
sudo ethtool -T end0            # hardware timestamping
systemctl --failed              # nothing
```

and for stage 2, with the FPGA design enabled:

```
cat /proc/mtd                   # mtd0: the board's flash
ls /dev/ttyS1                   # UART0 on the header
sudo dmesg | grep simple-framebuffer
cat /sys/class/hwmon/hwmon*/name | grep amc6821    # the fan controller
```

The fan runs at its loud power-on speed in stage 1; nothing can reach its controller without
the FPGA design. More tests of the header pins and of HDMI are in [tools/](tools/README.md).

## The Ethernet address

The board stores none. The first boot makes one up, a random address marked as locally
administered, and keeps it in `/etc/systemd/network/10-emac0.link`. To use another address,
change the `MACAddress=` line in that file and reboot. The interface is `end0`, Debian's usual
name for it.
