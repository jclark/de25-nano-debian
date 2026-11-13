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

Details are in the following pages:

- **[bringup.md](bringup.md)**: how to build everything needed from source and install it on
  a board.
- **[how-it-works.md](how-it-works.md)**: how the parts specific to this repository work:
  the boot arrangement, and the hardware support provided through the FPGA.

The bring-up, and this repository documenting it, were done using Claude Fable 5.2 under my
supervision.

## Known limits

- HDMI is 1920x1080 at 60 Hz only, with no monitor detection and no frame interrupt. One KVM
  device refusedsystem the signal; a monitor and another capture device accept it.
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
