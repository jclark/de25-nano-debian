# Debian on the Terasic DE25-Nano

This repository brings up Debian 13 on the [Terasic DE25-Nano](https://www.terasic.com.tw/)
(Altera Agilex 5 SoC FPGA):

- a kernel close to mainline, with the changes the board needs on their way upstream;
- Debian from the Debian archive;
- the board's hardware working under Linux: Ethernet with its PTP clock, the fan controller,
  HDMI, and a UART, I2C and SPI on the 40-pin header.

Everything is built from source on one x86 machine.

The motivating use is precise timing. The board's Ethernet PTP clock (PHC) can timestamp a
pulse-per-second (PPS) signal in hardware, so the DE25-Nano can serve as a PTP grandmaster
with [SatPulse](https://satpulse.net/), or as an NTP server with chrony using a PHC refclock
with `extpps`.

Everything here is source, or a pointer to source, and the steps from source to a running
board. There are no prebuilt binaries.

The bring-up, and this repository documenting it, were done using Claude Fable 5.2 under my
supervision.

## Two stages

**Stage 1: nothing flashed.** An SD card that boots a board as it comes from the factory:
Debian with the kernel built here, serial console, Ethernet with its PTP clock. Needs no Altera
software.

**Stage 2: one flash write over JTAG.** Adds the FPGA design from this repository, which
U-Boot loads from the SD card at every boot. It brings out on the 40-pin header (JP1) the PTP
clock's trigger input and pulse output, a UART, a spare I2C bus and SPI; it puts the fan
controller under Linux's control; and it shows the Linux console on HDMI at 1920x1080. After
the one flash write, a changed FPGA design is just a new file on the card.

Stage 2 needs Altera's Quartus Pro, which is free for this FPGA and comes as a Docker image
(17.5 GiB), both to build the design and to write the flash.

One SD card image serves both stages. It carries the FPGA design; a board with the factory
flash contents refuses the design and boots without it, and a board whose flash has been
written loads it.

## Booting

### Storage layout

| Storage | Holds | Written |
|---|---|---|
| QSPI flash, on the board | The first stage: the configuration of the SoC (the chip's ARM CPU and its peripherals, which Altera calls the HPS) and the first-stage loader. In stage 1 it has the factory contents, which also hold Terasic's FPGA design. In stage 2 it holds `de25-nano.hps.jic`, and no FPGA design. | Once, over JTAG, for stage 2 |
| SD card, partition 1: FAT, 64 MB, `/boot/firmware` | `u-boot.itb` (U-Boot with TF-A); `boot.scr`, the U-Boot script; `uboot.env`, U-Boot's saved settings, if any have been saved. Stage 2: `fpga.rbf`, the FPGA design. | By the image; later like any file |
| SD card, partition 2: ext4, the rest of the card, `/` | Debian. The kernel `/boot/vmlinuz-<release>` (gzip-compressed), its modules, and its device tree `/usr/lib/linux-image-<release>/intel/socfpga_agilex5_de25_nano.dtb`, all from the kernel package. The boot menu `/boot/extlinux/extlinux.conf`, written by Debian's `u-boot-update` from `/etc/default/u-boot`. Stage 2: the device tree overlay `/boot/dtbo/fpga.dtbo`. | By the image; later by installing packages, and like any file |

### Boot sequence

1. At power-on the chip reads the flash, configures the SoC and runs the first-stage loader
   from the flash. With the factory flash contents it configures the FPGA from the flash first.
2. The loader sets up the memory and loads `u-boot.itb` from partition 1. TF-A starts, then
   U-Boot.
3. U-Boot scans the bootable partitions. On partition 1 it runs `boot.scr`. The script sets
   three things U-Boot's own configuration for this board lacks: the name of the device tree
   file, the address overlays are loaded to, and the address and size limit for unpacking a
   compressed kernel. In stage 2 it also loads `fpga.rbf` into the FPGA.
4. On partition 2 it reads the boot menu. The menu has an entry for each installed kernel; the
   first, the newest, is the default. From the entry U-Boot loads the kernel, the device tree
   from that kernel's own directory and, in stage 2, the overlay, which it applies to the
   device tree.
5. The kernel file is gzip-compressed. U-Boot recognises that, unpacks it to the address
   `boot.scr` gave, moves the result back to the address it loads kernels at, and starts it
   with the device tree.
6. Linux starts with partition 2 as its root. In stage 2 a udev rule sets the fan curve and a
   unit sets up the HDMI transmitter.

The addresses, all in the board's 1 GB of RAM, which starts at 0x80000000:

| Address | Use | Set in |
|---|---|---|
| 0x82000000 | The kernel file is loaded here; the unpacked kernel is moved back here before it is started | U-Boot's configuration (`kernel_addr_r`) |
| 0x86000000 | The device tree | U-Boot's configuration (`fdt_addr_r`) |
| 0x87000000 | Each overlay, while it is applied | `boot.scr` (`fdtoverlay_addr_r`) |
| 0x90000000 | The kernel is unpacked here first | `boot.scr` (`kernel_comp_addr_r`; `kernel_comp_size` limits the compressed kernel to 32 MB) |
| 0xBF000000 | The HDMI frame buffer, 8 MB, in stage 2 | The FPGA design and its overlay |

## Stage 2 features

What the FPGA design adds, once the flash has been written.

### Header pins

The 40-pin header JP1 (GPIO 0) is the one along the edge of the board with the DC jack and the
USB-C sockets; the board has "GPIO_0" printed beside it. Pin 1 is at the DC-jack end, in the
row nearer the middle of the board: its solder pad on the underside is the square one. The
odd-numbered pins are that inner row; the even-numbered pins are the row at the board's edge.
The signals are 3.3 V logic.

| JP1 pin | Signal | Direction | In Linux |
|---|---|---|---|
| 3 | I2C SDA | both | a spare I2C bus |
| 5 | I2C SCL | both | a spare I2C bus |
| 7 | PPS out | output | PTP clock `/dev/ptp0`, periodic output channel 1 |
| 8 | UART0 TX | output | `/dev/ttyS1` |
| 9 | PPS in | input | PTP clock `/dev/ptp0`, external timestamp channel 1 |
| 10 | UART0 RX | input | `/dev/ttyS1` |
| 11 | 5 V (up to 1 A) | | |
| 12 | ground | | |
| 19 | SPI MOSI | output | SPI master 0 |
| 21 | SPI MISO | input | SPI master 0 |
| 23 | SPI SCLK | output | SPI master 0 |
| 24 | SPI SS0 | output | SPI master 0 |
| 29 | 3.3 V (up to 1.5 A) | | |
| 30 | ground | | |

The UART, I2C and SPI signals are on the pins where a Raspberry Pi has them. The power pins
are not where a Raspberry Pi has them: here 5 V is pin 11 and ground is pin 12, so a Raspberry
Pi add-on board cannot be plugged in, and a cable wired for a Raspberry Pi's power pins must
not be used as it is. Pins 1, 2, 4 and 6, which carry power on a Raspberry Pi, are left
unconnected.

The I2C pins have only the FPGA's weak internal pull-ups; a device on that bus may need its
own pull-up resistors.

### HDMI

HDMI output is a scan-out of a frame buffer in system RAM: logic in the FPGA reads the frame
buffer and drives the board's HDMI transmitter. Linux uses it as a `simple-framebuffer`
(`/dev/fb0`); there is no DRM driver. The mode is fixed at 1920x1080, 60 Hz.

```mermaid
flowchart LR
  con["Linux console,<br/>programs using /dev/fb0"] --> fb[("frame buffer:<br/>8 MB of system RAM<br/>at 0xBF000000")]
  fb --> vb["video block<br/>in the FPGA"] --> tx["HDMI transmitter<br/>chip, ADV7513"] --> mon["monitor"]
  ov["device tree overlay"] -. "reserves and describes" .-> fb
  init["de25-hdmi-init,<br/>at boot"] -. "sets up, over I2C" .-> tx
```

| Part | Where it is | What it does |
|---|---|---|
| Frame buffer | 8 MB of system RAM at 0xBF000000, reserved | Holds one frame: 1920x1080 pixels, 32 bits per pixel (`x8r8g8b8`) |
| Video block, `fpga/src/hdmi_scanout.sv` | In the FPGA design (`fpga.rbf`) | Generates the 1080p60 video timing from a 148.5 MHz pixel clock, and reads the frame buffer from system RAM once per frame through the SoC's FPGA-to-SDRAM bridge. It has no registers: it runs as soon as the FPGA design is loaded. |
| HDMI transmitter, ADV7513 | A chip on the board | Converts the FPGA's parallel RGB, sync and clock signals to HDMI |
| `de25-hdmi-init` and its systemd unit | In the Debian image, `/usr/local/sbin` | Configures the transmitter over I2C at every boot; the I2C bus reaches the chip through the FPGA. The output is always enabled and the monitor's EDID is not read. |
| Device tree overlay, `fpga.dtbo` | On the card | Reserves the 8 MB, and describes the frame buffer in a `simple-framebuffer` node |
| Kernel | `CONFIG_FB_SIMPLE`, from the config fragment | Provides `/dev/fb0` from that node |
| Boot menu | `console=tty0` | Puts the text console on the frame buffer |

The frame buffer's address and the resolution are defined in one place, the video block's
source; the overlay's build takes them from there.

### Fan

The fan is driven by a fan controller chip on the board (AMC6821). Linux can only reach it
through the FPGA design, so in stage 1 the fan runs at the chip's power-on speed, which is loud.

| Part | Where it is | What it does |
|---|---|---|
| Fan controller, AMC6821 | A chip on the board, on the same I2C bus as the HDMI transmitter | Drives the fan's PWM input and measures its speed; has its own temperature sensor (the board) and reads the FPGA's temperature diode |
| I2C route | In the FPGA design | Connects that I2C bus to the SoC's I2C0 controller |
| Device tree overlay, `fpga.dtbo` | On the card | Enables I2C0 and declares the controller, with the fan's PWM polarity inverted, as it is on this board |
| Kernel | The `amc6821` hwmon driver (a module in arm64 defconfig) | Provides the controller under `/sys/class/hwmon` |
| `60-de25-fan.rules` and `de25-fan-curve` | In the Debian image: `/etc/udev/rules.d`, `/usr/local/sbin` | The udev rule runs the script when the hwmon device appears; the script sets the fan curve |
| `/etc/default/de25-fan` | In the Debian image | The settings for the curve, read by the script |

The curve is held in the controller, which then follows the FPGA's temperature by itself; no
daemon is involved. The settings in `/etc/default/de25-fan`:

| Setting | Default | Meaning |
|---|---|---|
| `FAN_MIN_PWM` | 90 | The fan drive at its minimum, of 255: about 5,200 rpm |
| `FAN_MIN_TEMP` | 64 | The FPGA temperature, in °C, up to which the fan stays at the minimum |
| `FAN_FULL_TEMP` | 76 | The FPGA temperature at which the fan reaches full speed. The controller supports only certain slopes; with these defaults it settles on 74 °C. |

After changing them, reboot, or apply them at once with
`sudo udevadm trigger --action=add --subsystem-match=hwmon`. With the defaults, on one board
with Linux idle, the FPGA sits near 58 °C and the board sensor near 37 °C.

## Tasks

There are four tasks, each a build from source, each with a letter:

- **B**: U-Boot (the boot loader), with TF-A
- **K**: the kernel
- **F**: the FPGA design
- **I**: the SD card image

In the diagram a rectangle is a task, a slanted box is a file, a trapezoid is something you do
by hand, and a cylinder is storage on the board. Solid arrows are needed for stage 1; dashed
arrows only for stage 2.

```mermaid
flowchart LR
  P1["B: U-Boot, with TF-A"]
  P2["K: Kernel"]
  P3["F: FPGA design"]
  P4["I: SD card image"]
  itb[/"u-boot.itb"/]
  spl[/"first-stage loader<br/>u-boot-spl-dtb.hex"/]
  pkg[/"kernel package<br/>linux-image .deb"/]
  rbf[/"fabric<br/>fpga.rbf"/]
  dtbo[/"overlay<br/>fpga.dtbo"/]
  jic[/"flash image<br/>.jic"/]
  img[/"de25-nano.img"/]
  wc[/"Write the card"\]
  wf[/"Write the flash<br/>over JTAG"\]
  sd[("microSD card")]
  qspi[("QSPI flash")]
  P1 --> itb --> P4
  P1 --> spl -.-> P3
  P2 --> pkg --> P4
  P3 -.-> rbf -.-> P4
  P3 -.-> dtbo -.-> P4
  P3 -.-> jic -.-> wf -.-> qspi
  P4 --> img --> wc --> sd
```

| Task | Builds | Produces | Needs first | Tool | Instructions |
|---|---|---|---|---|---|
| B | U-Boot, with TF-A | `u-boot.itb` for the card; the first-stage loader for the flash image | nothing | Docker | [u-boot/README.md](u-boot/README.md) |
| K | Kernel | the kernel as a Debian package: kernel, modules and device trees | nothing | Docker | [kernel/README.md](kernel/README.md) |
| F | FPGA design | `fpga.rbf` and `fpga.dtbo` for the card; the flash image | the loader from Task B, for its last step | Docker with the Quartus image | [fpga/README.md](fpga/README.md) |
| I | SD card image | the card image, one for both stages | Tasks B and K, and Task F for the FPGA design | Docker, qemu-user | [sdimage/README.md](sdimage/README.md) |

Then two things done by hand:

- [install-card.md](install-card.md): write the card, first boot.
- [install-flash.md](install-flash.md): stage 2 only. Read the flash back, write it, and how to go back.

## Order of work

Tasks B, K and F do not depend on each other until the last step of Task F, so start all
three at once. Task I comes last.

```
u-boot/build.sh     # Task B, a few minutes
kernel/build.sh     # Task K, about six minutes on a 24-thread machine
fpga/build.sh       # Task F: pulls 17.5 GiB once, then about ten minutes
sdimage/build.sh    # Task I, five to ten minutes
```

For stage 1 alone, Task F can be left out. Task I then makes `de25-nano-nofpga.img`, the same
image without the FPGA design.

Each script fetches the sources it needs into `work/` and leaves its results in `out/`. Both
directories are created in this repository and are not in git.

If an agent is doing this for you, [AGENTS.md](AGENTS.md) tells it the order, what can run in
parallel, and where it must stop and ask you (writing the card, anything to do with the flash).

## What you need

- An x86-64 Linux machine with Docker and git, about 60 GB of free disk for stage 2 (the
  Quartus image unpacks to 34 GB) or 10 GB for stage 1, and a network connection.
- For Task I on x86: qemu-user with binfmt for aarch64 (Debian and Ubuntu: package
  `qemu-user-static`, or `qemu-user-binfmt`), because the Debian root filesystem is put together
  by running arm64 programs.
- A microSD card of 4 GB or more, and the board's USB-C cable for the serial console (and for
  JTAG in stage 2).

## What has been tested

All of this was developed on one board in November 2026.

| | State |
|---|---|
| Task B built by its script from a clean start | yes |
| Task K built by its script, cross-compiled on x86 | yes |
| Task F built by its script from a clean start | yes |
| Task I's image built from those and booted, with nothing changed by hand afterwards | yes, on a board in stage 2 |
| Stage 2 on the board: boots with nothing typed; first-boot set-up, with the two optional files; network; fan; HDMI console | yes |
| A GNSS receiver (u-blox M9) on the header: its PPS timestamped by the PTP clock, serial in both directions, SatPulse disciplining the PTP clock and chrony following it | yes |
| Installing a second kernel package on a running board | yes: the boot menu was rewritten with both |
| PPS output (JP1 pin 7), the spare I2C bus and SPI on their present pins | **not yet**: the PPS output and the UART worked in loop tests on the pins used before; I2C and SPI have only been seen to probe |
| Stage 1: the image on a board with untouched factory flash contents | **not yet**: a factory board refusing a foreign FPGA design and booting on was seen with an earlier card; this image has not been tried on one |
| Writing the read-back file to return to the factory state | **not yet**: the read-back verifies against the flash, the write back has not been needed |

## Known limits

- HDMI is 1920x1080 at 60 Hz only, with no monitor detection and no frame interrupt. One KVM
  device refused the signal; a monitor and another capture device accept it.
- The board stores no Ethernet address. The first boot of a card makes one up and keeps it, so
  the address belongs to the card, not the board.
- U-Boot and TF-A are built from Terasic's repositories, unchanged, with one configuration
  option added. The first-stage loader in the factory flash was built from the same source,
  which is why this U-Boot works on a factory board.
- The flash can only be written over JTAG with Altera's programmer. Writing it from U-Boot or
  Linux has not been made to work.

## Sources

| What | Where |
|---|---|
| Kernel | [jclark/linux](https://github.com/jclark/linux), branch `de25-nano-mainline/v7.4`: Linux 7.4-rc2 plus the board's device tree and Ethernet PTP changes on their way upstream |
| U-Boot | [terasic/u-boot-socfpga](https://github.com/terasic/u-boot-socfpga), branch `de25-nano-v2025.01` |
| TF-A | [terasic/arm-trusted-firmware](https://github.com/terasic/arm-trusted-firmware), branch `de25-nano-v2.12.0` |
| FPGA design | [altera-fpga/agilex5-ed-hps-baseline](https://github.com/altera-fpga/agilex5-ed-hps-baseline), tag `QPDS26.1.1_REL_GSRD_PR`, directory `terasic-de25-nano-devkit/baseline-a55`, with the changes in [fpga/](fpga/) |
| Quartus Pro 26.1.1 | Docker Hub, `alterafpga/quartus-pro:26.1.1-agilex5` |
| Debian | the Debian archive, release 13 (trixie) |

## Licence

The files written for this repository are under the MIT licence ([LICENSE](LICENSE)), except
where a file says otherwise. `fpga/top-level.patch` is a change to files of Altera's design,
which is also MIT-licensed.
