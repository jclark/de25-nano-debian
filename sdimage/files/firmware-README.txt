DE25-Nano SD card, FAT partition (mounted at /boot/firmware in Linux)

u-boot.itb   U-Boot. The loader in the board's flash starts it.
boot.scr     U-Boot script, run at every boot.
fpga.rbf     The FPGA design. Not here on a new card: "sudo de25-fpga enable" on the board
             puts it here. U-Boot loads it at every boot once the board's flash has been
             written.

write-on-boot.rpd         New flash contents and their crc32, put here by
write-on-boot.txt         "sudo de25-fpga enable". U-Boot writes the contents to the flash at
                          the next boot and removes both files.
saved-<crc32>.rpd         What the flash held before U-Boot wrote it (saved-f2447995.rpd:
                          Terasic's factory contents). Keep a copy elsewhere;
                          "sudo de25-fpga restore" writes it back.
write-on-boot-failed.txt  Written by U-Boot if the flash write failed: the step it failed in.

Before the first boot of this card you may add two files here. They are read once, at the
first boot:

hostname          One line: the name for this board. Without it the name is @HOSTNAME@.
authorized_keys   ssh public keys, one a line, for the user "@USER@". With this file, ssh
                  accepts keys only. Without it, log in as @USER@ with the password @USER@;
                  the password has to be changed at the first login.
