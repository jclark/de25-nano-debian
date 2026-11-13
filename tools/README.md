# Tests to run on the board

Copy what you need to the board. All of these are for stage 2.

## The PTP clock's trigger input and pulse output

With a jumper from JP1 pin 32 (pulse output) to pin 31 (trigger input), the clock timestamps
its own pulses. `testptp` is the kernel's own test program,
`tools/testing/selftests/ptp/testptp.c` in the kernel source; compile it for arm64, on the
board with `gcc` or with the cross-compiler, against the headers of this kernel
(`make headers_install`).

```
sudo ./testptp -d /dev/ptp0 -i 1 -p 1000000000     # a pulse every second on output 1
sudo ./testptp -d /dev/ptp0 -i 1 -e 5              # five timestamps from input 1
```

A good result is five events on index 1, one second apart, each a few nanoseconds after the
second (`...000000015`).

For a GNSS receiver: its pulse per second on pin 31 (3.3 V logic), its serial lines on pins
33 and 34, 3.3 V on pin 29, ground on pin 30.

## UART0

With a jumper from JP1 pin 34 (TX) to pin 33 (RX):

```
python3 uart-loop.py /dev/ttyS1
```

prints `sent 224 received 224 match True`.

## HDMI

With a monitor connected. `hdmi-test.py` writes test pictures straight into the frame buffer
(`/dev/fb0`); run it as root.

```
sudo python3 hdmi-test.py pattern        # colour bars, ramps and fine lines
sudo python3 hdmi-test.py sweep 5        # step the transmitter's clock delay, 5 s each
sudo python3 hdmi-test.py move 10        # a moving bar: a heavy load on the memory
```

`sweep` is for finding the range of clock delays that gives a clean picture after the FPGA
design's HDMI pin timing has changed; the delay in use is set in
`/usr/local/sbin/de25-hdmi-init`.

To put the text console back afterwards: `printf '\033c' | sudo tee /dev/tty1` and
`sudo systemctl restart getty@tty1`.

## Fan

```
grep . /sys/class/hwmon/hwmon*/name          # find amc6821
cat /sys/class/hwmon/hwmonN/fan1_input       # rpm
cat /sys/class/hwmon/hwmonN/temp2_input      # the FPGA's temperature, millidegrees
```

The curve is set by `/usr/local/sbin/de25-fan-curve`.
