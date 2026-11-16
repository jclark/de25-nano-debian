# Example: a design built on the base

The smallest design that uses the hooks: a 1 Hz square wave on JP1 pin 31, which the base
leaves unconnected. [../README.md](../README.md), "Building on this design", explains the
hooks; this directory shows the files.

| File | What it is |
|---|---|
| `core.conf` | `NAME=example`: the core's name, and so its output directory and its package |
| `ext/ports.svh` | The port it adds to the top level |
| `ext/logic.svh` | Its logic. It takes the place of the base's file, so it also ties off the interrupt lines and the timestamp hubs' counter input, as the base does |
| `assignments.qsf` | The pin for the new port |
| `overlay/example.dtso` | Its addition to the device tree overlay |

It has no Platform Designer scripts and no connections to the SoC system, so it has no
`platform-designer.txt` and no `ext/connections.svh`.

```
fpga/build.sh fpga/example
packages/mkdeb-core example 0.1 out/fpga/example out/packages
```

The first command leaves `fpga.rbf` and `fpga.dtbo` in `out/fpga/example/`; the second makes
`de25-nano-core-example_0.1_arm64.deb`. On a board, after installing the package:
`sudo de25-fpga select example` and a reboot.
