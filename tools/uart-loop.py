import os,termios,time,sys
dev=sys.argv[1]
fd=os.open(dev,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
a=termios.tcgetattr(fd)
a[0]=0;a[1]=0;a[2]=termios.CS8|termios.CREAD|termios.CLOCAL;a[3]=0
a[4]=a[5]=termios.B115200
termios.tcsetattr(fd,termios.TCSANOW,a)
time.sleep(0.2); termios.tcflush(fd,termios.TCIOFLUSH)
tok=b"de25-uart0-loop-0123456789-"*8
os.write(fd,tok); time.sleep(0.5)
try: r=os.read(fd,4096)
except BlockingIOError: r=b""
print(dev,"sent",len(tok),"received",len(r),"match",r==tok)
