# Write the card, first boot

Needs: an image from piece 4 ([sdimage/README.md](sdimage/README.md)), a microSD card of 4 GB or
more, the board's USB-C cable.

Use the stage 1 image on a board with factory flash contents. Use the stage 2 image only
after the flash has been written ([install-flash.md](install-flash.md)); with a factory flash
the FPGA design on a stage 2 card is refused and what depends on it does not work.

## Write the card

Find the card's device name (`lsblk`), make sure nothing on it is mounted, then:

```
sudo dd if=out/sdimage/de25-nano-stage1.img of=/dev/sdX bs=4M conv=fsync status=progress
```

This overwrites the whole card. Keep the card that came with the board as it is: it is the
way back to the vendor's system.

## Serial console

The board's USB-C socket gives a USB hub with two serial ports and the JTAG cable. The
processor's console is the port that Linux on the PC lists as

```
/dev/serial/by-id/usb-TERASIC_DE25-Nano_<serial number>-if02-port0
```

at 115200 baud, 8 bits, no parity, for example `picocom -b 115200 <that path>`.

## First boot

Put the card in, connect Ethernet, power the board. On the console, in this order:

1. `U-Boot SPL 2025.01-...`: the first-stage loader from the flash. It sets up the memory and
   loads `u-boot.itb` from the card.
2. `U-Boot 2025.01-gd0f8813fd6bf (<date of your build>)`, then a five second countdown. A key
   stops it at the prompt `SOCFPGA_AGILEX5 #`; `boot` carries on.
3. `Found U-Boot script /boot.scr`. With a stage 1 card: `No fpga.rbf on the card`. With a
   stage 2 card: `FPGA reconfiguration OK!`. Then `SCRIPT FAILED: continuing...`, which is
   what U-Boot prints when any script returns, not a fault.
4. `Found /boot/extlinux/extlinux.conf`, the kernel and the device tree are fetched (and the
   overlay, for stage 2), `Starting kernel ...`.
5. Debian's login prompt. The first boot takes a little longer: it makes the ssh host keys and
   grows the root partition to the size of the card.

Log in as `debian`: with your ssh key if you gave one when building the image, or with the
password `debian`, which then has to be changed at once. `sudo` asks for no password.

If the SPL says `mmc init failed with error: -95`, the card is not seated; it can pop out when
cables are handled.

## Check

```
uname -r                        # the kernel built in piece 2
ip -br addr show eth0           # an address from DHCP
ls /sys/class/ptp/              # ptp0: the Ethernet MAC's clock
sudo ethtool -T eth0            # hardware timestamping
systemctl --failed              # nothing
```

and for stage 2:

```
ls /dev/ttyS1                   # UART0 on the header
sudo dmesg | grep simple-framebuffer
cat /sys/class/hwmon/hwmon*/name | grep amc6821    # the fan controller
```

The fan runs at its loud power-on speed in stage 1; nothing can reach its controller without
the FPGA design. More tests of the header pins and of HDMI are in [tools/](tools/README.md).

## The Ethernet address

The board stores none. If the image was built without `MAC=`, U-Boot invents an address at
every boot. To fix one on a running system, create `/etc/systemd/network/10-emac0.link`:

```
[Match]
Path=platform-10810000.ethernet

[Link]
MACAddress=02:de:25:00:00:01
NamePolicy=kernel
```
