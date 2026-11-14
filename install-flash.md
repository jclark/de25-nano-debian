# Write the flash (stage 2)

The board's QSPI flash holds the first-stage image: the SoC's configuration and the
first-stage loader. Stage 2 replaces it once with the first-stage image from Task F
([fpga/README.md](fpga/README.md)). After that the FPGA design itself is a file on the SD card.

There are two ways to write it:

- **From the board**: one command, a reboot and a power cycle. It needs no other machine and
  no Altera tools.
- **Over JTAG**, with Altera's programmer in the Quartus container. It works whatever the
  flash holds, so it is also how a board that does not start is recovered.

## From the board

Needs: the board running from a card made from `de25-nano.img`
([install-card.md](install-card.md)), with the factory flash contents. Where the flash
already holds this first-stage image, `enable` only enables the design.

### 1. Ask for it

```
sudo de25-fpga enable
```

It says what will happen and asks for confirmation (`--force` does it without asking). It
does not touch the flash yet: it puts the new flash contents and the FPGA design where the
next boot finds them. `sudo de25-fpga disable` undoes it.

### 2. Reboot, and watch the LED

```
sudo reboot
```

U-Boot then does the work, which should take about two minutes:

- it checks the new contents against their crc32;
- it saves what the flash holds to the card's FAT partition, as `saved-<crc32>.rpd`, and
  reads the file back; for a board as Terasic ships it that is `saved-f2447995.rpd`;
- it erases the flash, writes the new contents, reads them back and compares.

The LED to watch is `HPS_LED`: the single LED beside the two small push-buttons marked
`HPS RST` and `HPS KEY`, next to the slide switches. (The row of eight LEDs along the edge is
not it.)

| LED | Meaning |
|---|---|
| One second on, one second off | Working. Leave the power alone. |
| Steady on | Written and verified. Go on to step 3. |
| Four times a second | It failed: see [If it failed](#if-it-failed). |

The serial console shows the same, with each step named.

### 3. Power cycle

When the LED is steady on, unplug the board's power and the USB-C cable (the cable alone
keeps part of the board powered), wait a few seconds, and plug both in again. The chip takes
up new flash contents only at power-on.

The board boots with the FPGA design loaded: U-Boot prints `FPGA reconfiguration OK!` and
applies the device tree overlay, and the header signals, the fan control and HDMI are there.

`sudo de25-fpga status` says how things stand at any time. Copy `saved-f2447995.rpd`, or
whichever `saved-<crc32>.rpd` is on the card, from the FAT partition to another computer as
well.

### If it failed

The console names the step that failed. Power cycle as in step 3; `sudo de25-fpga status`
then repeats it. The write is not tried again by itself: `sudo de25-fpga enable` asks for it
again, and `sudo de25-fpga disable` gives it up.

If it failed before the erase, the flash is as it was and the board boots as before. If it
failed in or after the erase (while erasing, writing or comparing), the board may not start; the flash is then written over JTAG,
below, leaving out step 2: `saved-<crc32>.rpd` on the card is the copy of the old contents.

### Going back to the factory state

```
sudo de25-fpga restore
sudo systemctl halt
```

`restore` stops the FPGA design being loaded and writes `saved-f2447995.rpd` back
(`sudo de25-fpga restore FILE` for a file kept elsewhere). Then power cycle as in step 3. The
board boots the same card in stage 1.

## Over JTAG

Needs: Task F built; the Quartus container (`fpga/q`); the board's USB-C cable from the
machine with the container to the board; the board powered (with a card that boots, for
step 2).

Run the commands from the top of the repository. `fpga/q --usb` runs the Quartus container as
root with access to USB. Altera's programmer reads and writes `.jic` files; Task F makes
`out/fpga/de25-nano.hps.jic` with the same flash contents as `de25-nano.hps.rpd`.

### 1. See the board on JTAG

```
fpga/q --usb jtagconfig -n
```

It lists `DE25-Nano [...]` with one device (ID `4362C0DD`) on a factory board. If a first
stage of this kind ("HPS first") is already running, it lists two devices, the CPU's
debug port first and the FPGA second; see step 4.

### 2. Read the flash back and keep the file

Any flash operation over JTAG stops the CPU, so shut Linux down first
(`sudo systemctl halt` on the board) and leave the board powered.

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IE;out/fpga/readback.jic;MT25QU128"
```

About half a minute; nothing is written to the board. Copy `out/fpga/readback.jic` somewhere
safe: it is this board's flash contents. Terasic's own flash file cannot be used in its
place with this version of Quartus (it names the FPGA in a way the programmer refuses), and
converting Terasic's design again does not reproduce the factory contents.

Check that the file is good, again without writing:

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IV;out/fpga/readback.jic"
```

### 3. Write

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IPV;out/fpga/de25-nano.hps.jic"
```

It erases, programs and verifies in about half a minute, and reports success.

### 4. If the write fails at once with "Invalid parameter"

That happens when the board was running an "HPS first" image, that is, when the flash has
already been written this way before: the JTAG chain then has two devices and the FPGA is the
second. Run the command once with `@2` after the file name:

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IPV;out/fpga/de25-nano.hps.jic@2"
```

It loads its helper into the FPGA, the CPU drops off the chain, and the command fails
with "JTAG chain broken". Nothing has been written. Now run the plain command of step 3; the
chain is the FPGA alone and it works.

### 5. Power cycle, and enable the FPGA design

Power cycle as in step 3 of the first way. The board boots from the card as before: the same
U-Boot works with the factory flash contents and with these. Then, on the board:

```
sudo de25-fpga enable
sudo reboot
```

### Going back to the factory state over JTAG

On the board, `sudo de25-fpga disable`, then `sudo systemctl halt`. Write the read-back from
step 2 in the same way as step 3 (with step 4 if it fails at once), then power cycle:

```
fpga/q --usb quartus_pgm -m jtag -c 1 -o "IPV;out/fpga/readback.jic"
```
