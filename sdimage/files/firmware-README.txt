DE25-Nano SD card, FAT partition (mounted at /boot/firmware in Linux)

u-boot.itb   U-Boot. The loader in the board's flash starts it.
boot.scr     U-Boot script, run at every boot.
fpga.rbf     The FPGA design, if the image was built with it. U-Boot loads it at every boot.
             A board whose flash still has the factory contents refuses it and boots without.

Before the first boot of this card you may add two files here. They are read once, at the
first boot:

hostname          One line: the name for this board. Without it the name is @HOSTNAME@.
authorized_keys   ssh public keys, one a line, for the user "@USER@". With this file, ssh
                  accepts keys only. Without it, log in as @USER@ with the password @USER@;
                  the password has to be changed at the first login.
