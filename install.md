# Install

This page is for installing the released card image on a DE25-Nano. Nothing has to be built,
and no software from Altera is needed.

You need the board with its power supply, a microSD card of 4 GB or more with a card reader,
and an Ethernet connection to a network with DHCP. Keep the microSD card that came with the
board as it is: putting it back is how you return to Terasic's system.

## Write the card

Download `de25-nano-v0.1.img.xz` from the
[releases page](https://github.com/jclark/de25-nano-debian/releases).

Write it to the card with [balenaEtcher](https://etcher.balena.io/), which runs on Windows,
macOS and Linux: choose the downloaded file (it does not need unpacking), choose the card,
and start. Raspberry Pi Imager does the same job with its "Use custom" choice. On Linux the
command line works too, with the card's device name in place of `sdX`:

```
xzcat de25-nano-v0.1.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync
```

If you log in with ssh keys, you can give the card your public keys now. Take the card out
and put it back in; it shows up as a small drive called `FIRMWARE`. Copy your public key
file there under the name `authorized_keys`. A file called `hostname`, containing one word,
names the board; without it the name is `de25-nano`.

## Start the board

Put the card in the board, connect Ethernet and plug in the power. The fan is loud at this
stage. After about a minute the board is on the network. Find its address in your router's
list of devices, where it appears under its name, and log in as the user `debian`:

```
ssh debian@<address>
```

With an `authorized_keys` file on the card, your key is accepted and passwords are not.
Without one, the password is `debian`, and you are asked to choose a new one straight away.
`sudo` does not ask for a password.

The board is now running Debian with its network port, and that is all: HDMI, the fan
control and the signals on the 40-pin GPIO header need the FPGA design, which is the next step.

## Enable the FPGA design

The board's flash chip holds Terasic's own FPGA design. This step replaces the contents of
the flash, after saving them to the card, so that the board loads the FPGA design from the
card at every boot.

```
sudo de25-fpga enable
sudo reboot
```

The first command explains what will happen and asks for confirmation. Nothing is written
until the reboot. During the reboot, watch the small LED beside the two push-buttons marked
`HPS RST` and `HPS KEY`, next to the slide switches:

| LED | Meaning |
|---|---|
| One second on, one second off | Working. Leave the power connected. |
| Steady on | Finished. Unplug the power, wait a few seconds, and plug it in again. |
| Blinking fast | It failed. See [flash-jtag.md](flash-jtag.md). |

It takes about two minutes. After the power has been unplugged and plugged in again, the
board starts with the FPGA design loaded: the fan goes quiet, a monitor on the HDMI socket
shows the console, and the GPIO header signals listed in [how-it-works.md](how-it-works.md) are
there.

The saved flash contents are on the card's `FIRMWARE` drive as a file named
`saved-` followed by eight characters, ending in `.rpd`. Copy it to another computer as well.

## Going back

To put the saved flash contents back:

```
sudo de25-fpga restore
sudo systemctl halt
```

Then unplug the power and plug it in again. The board runs this card as it did before the
FPGA design was enabled. With Terasic's card in place of this one, it is as it came.

`sudo de25-fpga status` shows at any time whether the design is enabled and what the flash
holds.
