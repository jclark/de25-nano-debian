# Write the flash over JTAG (stage 2)

The board's QSPI flash holds the first stage: how the processor is set up and the first-stage
loader. Stage 2 replaces it once with `out/fpga/de25-nano.hps.jic` from piece 3
([fpga/README.md](fpga/README.md)). After that the FPGA design itself is a file on the SD card.

Needs: piece 3 built; the Quartus container (`fpga/q`); the board's USB-C cable from the
machine with the container to the board; the board powered, with a card that boots (a stage 1
card is fine).

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
stage of this kind ("HPS first") is already running, it lists two devices, the processor's
debug port first and the FPGA second; see step 4.

## 2. Read the flash back and keep the file

Any flash operation stops the processor, so shut Linux down first (`sudo systemctl halt` on
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

It loads its helper into the FPGA, the processor drops off the chain, and the command fails
with "JTAG chain broken". Nothing has been written. Now run the plain command of step 3; the
chain is the FPGA alone and it works.

## 5. Power cycle

Unplug the board's power and the USB-C cable (the cable alone keeps part of the board
powered), wait a few seconds, plug both in again.

The board boots from the card as before: the same U-Boot works with the factory first stage
and with this one. With a stage 1 card nothing else has changed yet.

## 6. Put the FPGA design on the card

Either write a stage 2 image ([install-card.md](install-card.md)), or add the two files to
the running stage 1 card ("From stage 1 to stage 2" in [sdimage/README.md](sdimage/README.md)).
At the next boot U-Boot prints `FPGA reconfiguration OK!`.

## Going back to the factory state

Write the read-back from step 2 the same way, then power cycle:

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IPV;out/fpga/readback.jic"
```

This write has not been tried; the read-back has only been verified against the flash (the
`IV` command above). Remove `fpga.rbf` from the card as well, or U-Boot will try to load it
and report that it was refused; the boot carries on either way.

## What has been done on the board this was developed on

The flash was read back, then written several times in this way with first-stage images made
by the same commands, and the board has run from the last of them since. The exact file your build
produces differs from the one in that board's flash at least in the loader's build date.
