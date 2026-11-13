# Write the flash over JTAG (stage 2)

The board's QSPI flash holds the first stage: the SoC's configuration and the first-stage
loader. Stage 2 replaces it once with `out/fpga/de25-nano.hps.jic` from Task F
([fpga/README.md](fpga/README.md)). After that the FPGA design itself is a file on the SD card.

Needs: Task F built; the Quartus container (`fpga/q`); the board's USB-C cable from the
machine with the container to the board; the board powered, with a card that boots (the card
from [install-card.md](install-card.md); it is used before and after).

Read all of this page before starting. A wrong or interrupted write leaves a board that does
not start until the flash is written again over JTAG; the read-back in step 2 is what you
would write to get the factory state back.

Run the commands from the top of the repository. `fpga/q --usb` runs the Quartus container as
root with access to USB.

## 1. See the board on JTAG

```
fpga/q --usb jtagconfig -n
```

It lists `DE25-Nano [...]` with one device (ID `4362C0DD`) on a factory board. If a first
stage of this kind ("HPS first") is already running, it lists two devices, the CPU's
debug port first and the FPGA second; see step 4.

## 2. Read the flash back and keep the file

Any flash operation stops the CPU, so shut Linux down first (`sudo systemctl halt` on
the board) and leave the board powered.

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IE;out/fpga/readback.jic;MT25QU128"
```

About half a minute; nothing is written to the board. Copy `out/fpga/readback.jic` somewhere
safe: it is this board's factory flash contents. Terasic's own flash file cannot be used in
its place with this version of Quartus (it names the FPGA in a way the programmer refuses),
and converting Terasic's design again does not reproduce the factory contents.

Check that the file is good, again without writing:

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IV;out/fpga/readback.jic"
```

## 3. Write

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IPV;out/fpga/de25-nano.hps.jic"
```

It erases, programs and verifies in about half a minute, and reports success.

## 4. If the write fails at once with "Invalid parameter"

That happens when the board was running an "HPS first" image, that is, when the flash has
already been written this way before: the JTAG chain then has two devices and the FPGA is the
second. Run the command once with `@2` after the file name:

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IPV;out/fpga/de25-nano.hps.jic@2"
```

It loads its helper into the FPGA, the CPU drops off the chain, and the command fails
with "JTAG chain broken". Nothing has been written. Now run the plain command of step 3; the
chain is the FPGA alone and it works.

## 5. Power cycle

Unplug the board's power and the USB-C cable (the cable alone keeps part of the board
powered), wait a few seconds, plug both in again.

The board boots from the card as before: the same U-Boot works with the factory first stage
and with this one.

## 6. Enable the FPGA design

The card carries the FPGA design, but the design is not loaded until it has been enabled. On
the board:

```
sudo de25-fpga enable
sudo reboot
```

From this boot on U-Boot prints `FPGA reconfiguration OK!`, applies the device tree overlay,
and the header signals, the fan control and HDMI are there.

A card made from `de25-nano-nofpga.img` has no FPGA design to enable: "Changing the card
later" in [sdimage/README.md](sdimage/README.md).

## Going back to the factory state

On the board, stop the FPGA design being loaded, and shut Linux down:

```
sudo de25-fpga disable
sudo systemctl halt
```

Write the read-back from step 2 in the same way as step 3 (with step 4 if it fails at once),
then power cycle as in step 5:

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IPV;out/fpga/readback.jic"
```

The board then boots the same card in stage 1.

## What has been done on the board this was developed on

The flash was read back, then written several times in this way with first-stage images made
by the same commands. The factory contents were written back once, from Linux, not with the
command above, and the card booted and restarted on them. The exact file your build
produces differs from the images that board has run: in the loader's build date, and in that
the loader is now built with `u-boot/qspi-flash.patch`.
