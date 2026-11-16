# DE25-Nano image: put the system administration directories on every user's path, as they
# are on root's. Debian leaves them off, so that a command such as de25-fpga, in /usr/sbin,
# is "not found" for the user even though "sudo de25-fpga" finds it.
case ":$PATH:" in
    *:/usr/sbin:*) ;;
    *) PATH=$PATH:/usr/local/sbin:/usr/sbin ;;
esac
