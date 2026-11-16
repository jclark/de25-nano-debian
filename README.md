# Debian on the Terasic DE25-Nano

This repository provides a Debian 13 card image for the
[Terasic DE25-Nano](https://www.terasic.com.tw/) (Altera Agilex 5 SoC FPGA), and everything
needed to build it from source. With it the board's hardware works under Linux: Ethernet
with its PTP clock, the fan controller, HDMI, and a UART, I2C, SPI and PPS signals on the
40-pin GPIO headers. What is not Debian's comes as Debian packages, so a running board is
updated by installing newer ones, and other FPGA designs can be built on the one here and
installed beside it.

The motivating use is precise timing. The board's Ethernet PTP clock (PHC) can timestamp a
pulse-per-second (PPS) signal in hardware, so the DE25-Nano can serve as a PTP grandmaster
with [SatPulse](https://satpulse.net/), or as an NTP server with chrony using a PHC refclock
with `extpps`.

There are two ways to use it:

- **[install.md](install.md)**: install the released card image on a board, and update it
  later. Nothing has to be built.
- **[build.md](build.md)**: build everything from source.

**[how-it-works.md](how-it-works.md)** explains the parts specific to this repository: the
boot arrangement, how the flash and the card are kept in step, and the hardware support
provided through the FPGA. To build your own FPGA design on this one, see "Building on this
design" in [fpga/README.md](fpga/README.md).

The bring-up, and this repository documenting it, were done using Claude Fable 5.2 under my
supervision.

## What is in the image

- **Boot loader:** Terasic's U-Boot for the board, built with some additional configuration
  options and some patches, the most significant of which allows it to write the board's
  flash.
- **Secure firmware:** Terasic's TF-A for the board.
- **Kernel:** Linux 7.4-rc3 with Ethernet driver fixes.
- **Device tree:** Altera's device tree for the board, ported to the mainline kernel, and an
  overlay for what the FPGA's core image adds.
- **User space:** Debian 13 (trixie) from the Debian archive.
- **FPGA bitstream:** built with Quartus Pro 26.3 from
  - Altera's HPS-first reference design for the board;
  - a custom video block, which drives the HDMI transmitter from a frame buffer;
  - connections from the GPIO headers and the fan controller to the SoC.

  It is in two parts, as Altera's HPS boot first mode has it: the HPS image, in the board's
  flash, and the core image, on the card. Several core images can be installed, and one is
  selected to load at boot.
- **Packages:** the boot chain (the HPS image, U-Boot and its script), the core image, and
  the command that manages them, `de25-fpga`, are Debian packages, as the
  kernel is.

The sources and their exact versions are in [build.md](build.md) and the pages it links to.

## Known limits

- HDMI is 1920x1080 at 60 Hz only, with no monitor detection and no frame interrupt. One KVM
  device refused the signal; a monitor and another capture device accept it.
- The board stores no Ethernet address. The first boot of a card makes one up and keeps it, so
  the address belongs to the card, not the board.
- U-Boot and TF-A are Terasic's and not mainline. The SPL in a board's factory flash was
  built from the same source, which is why this U-Boot works on a factory board.
- There is no package repository yet: updates are `.deb` files from the releases page,
  installed by hand.

## Licence

The files written for this repository are under the MIT licence ([LICENSE](LICENSE)), except
where a file says otherwise. `fpga/top-level.patch` is a change to files of Altera's design,
which is also MIT-licensed.
