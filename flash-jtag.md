# Writing the flash over JTAG

The usual way to write the board's flash is from the board itself, with
`sudo de25-flash write` ([install.md](install.md)). This page is for the two cases where
that is not enough: a write from the board that failed, and writing the flash with Altera's
programmer.

## If a write from the board failed

The LED blinks fast, and the serial console names the step that failed. Unplug the power and
plug it in again.

If the board starts, the flash is as it was: the failure came before anything was erased.
`sudo de25-flash status` repeats the step that failed. `sudo de25-flash write` asks for the
write again; removing `write-on-boot.rpd` from the `FIRMWARE` drive gives it up.

If the board does not start, the failure came while the flash was being erased, written or
compared, and the flash has to be written over JTAG as described below. The contents it had
before are on the card, in the `saved-` file on the `FIRMWARE` drive.

## Writing with Altera's programmer

This needs the FPGA design built from source ([build.md](build.md)), which provides the
Quartus container and the file to write, `out/fpga/base/hps.jic`. (A release also carries
that file, but writing it needs the Quartus container all the same.) Connect the board's
USB-C cable to the machine with the container, and power the board. Run the commands from
the top of the repository.

1. Shut Linux down on the board, if it is running, with `sudo systemctl halt`, and leave the
   power on. Any flash operation over JTAG stops the CPU.

2. Check that the board answers:

   ```
   fpga/q --usb jtagconfig -n
   ```

   It lists `DE25-Nano` with one device on a board with the factory flash contents, and with
   two on a board that is running an image written from this repository.

3. Read the flash back and keep the file. Nothing is written to the board:

   ```
   fpga/q --usb quartus_pgm -m jtag -c 1 -o "IE;out/fpga/base/readback.jic;MT25QU128"
   ```

   This is the file to write if you want the present contents back later. Terasic's own
   flash file cannot be used for that with this version of Quartus.

4. Write:

   ```
   fpga/q --usb quartus_pgm -m jtag -c 1 -o "IPV;out/fpga/base/hps.jic"
   ```

   It erases, writes and verifies in about half a minute.

   If it fails at once with "Invalid parameter", the board was running an image written from
   this repository, and step 2 listed two devices. Run the command once with `@2` after the
   file name; it fails with "JTAG chain broken" and writes nothing, but leaves the board
   ready. Then run the command above again.

5. Unplug the power, wait a few seconds, and plug it in again. Then, on the board:

   ```
   sudo de25-flash write
   sudo de25-fpga select base
   sudo reboot
   ```

   `de25-flash write` finds that the flash already holds the HPS image, if the file written
   was the one in the installed boot package, and only puts that package's `u-boot.itb` and
   `boot.scr` on the card. If the file was a newer build than the card has, `de25-fpga
   select` cannot see that the core fits: install the matching packages on the card, or use
   `sudo de25-fpga select --force base`.

To put back contents read in step 3, do the same with that file in step 4, after
`sudo de25-fpga disable` on the board.
