# Debian on the Terasic DE25-Nano

This repository brings up Debian 13 on the [Terasic DE25-Nano](https://www.terasic.com.tw/)
(Altera Agilex 5 SoC FPGA):

- a kernel close to mainline, with the board's device tree and with Ethernet PTP changes that
  are planned for submission upstream;
- Debian from the Debian archive;
- the board's hardware working under Linux: Ethernet with its PTP clock, the fan controller,
  HDMI, and a UART, I2C and SPI on the 40-pin header.

The motivating use is precise timing. The board's Ethernet PTP clock (PHC) can timestamp a
pulse-per-second (PPS) signal in hardware, so the DE25-Nano can serve as a PTP grandmaster
with [SatPulse](https://satpulse.net/), or as an NTP server with chrony using a PHC refclock
with `extpps`.

There are no prebuilt binaries at present. This repository says how to build a working system
from the parts listed under [Where the parts come from](#where-the-parts-come-from).

Details are in the following pages:

- **[bringup.md](bringup.md)**: how to build everything needed from source and install it on
  a board.
- **[how-it-works.md](how-it-works.md)**: how the parts specific to this repository work:
  the boot arrangement, and the hardware support provided through the FPGA.

The bring-up, and this repository documenting it, were done using Claude Fable 5.2 under my
supervision.

## Known limits

- HDMI is 1920x1080 at 60 Hz only, with no monitor detection and no frame interrupt. One KVM
  device refused the signal; a monitor and another capture device accept it.
- The board stores no Ethernet address. The first boot of a card makes one up and keeps it, so
  the address belongs to the card, not the board.
- U-Boot and TF-A are built from Terasic's repositories: TF-A unchanged, U-Boot with a patch
  and a few configuration options ([u-boot/README.md](u-boot/README.md)). The first-stage loader in the factory flash was
  built from the same source, which is why this U-Boot works on a factory board.

## Where the parts come from

- **Boot loader:** U-Boot, from
  [terasic/u-boot-socfpga](https://github.com/terasic/u-boot-socfpga), branch
  `de25-nano-v2025.01`, with the patch in [u-boot/](u-boot/).
- **Secure firmware:** TF-A, from
  [terasic/arm-trusted-firmware](https://github.com/terasic/arm-trusted-firmware), branch
  `de25-nano-v2.12.0`.
- **Kernel:** Linux 7.4-rc2 with the board's device tree and with Ethernet PTP changes that
  are planned for submission upstream, from [jclark/linux](https://github.com/jclark/linux), branch
  `de25-nano-mainline/v7.4`.
- **User space:** Debian 13 (trixie), from the Debian archive.
- **FPGA bitstream:** compiled with Quartus Pro 26.1.1 (Docker Hub,
  `alterafpga/quartus-pro:26.1.1-agilex5`) from:
  - Altera's reference design for the board:
    [altera-fpga/agilex5-ed-hps-baseline](https://github.com/altera-fpga/agilex5-ed-hps-baseline),
    tag `QPDS26.1.1_REL_GSRD_PR`, directory `terasic-de25-nano-devkit/baseline-a55`;
  - an HDMI video block written for this repository:
    [fpga/src/hdmi_scanout.sv](fpga/src/hdmi_scanout.sv), SystemVerilog, with its testbench in
    [fpga/sim/](fpga/sim/);
  - the changes in [fpga/](fpga/) that connect the video block, the header signals and the
    board's I2C bus to the SoC.

## Licence

The files written for this repository are under the MIT licence ([LICENSE](LICENSE)), except
where a file says otherwise. `fpga/top-level.patch` is a change to files of Altera's design,
which is also MIT-licensed.
