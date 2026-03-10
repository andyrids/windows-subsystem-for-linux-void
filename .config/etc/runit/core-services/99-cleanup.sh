if [ ! -e /var/log/wtmp ]; then
        install -m0664 -o root -g utmp /dev/null /var/log/wtmp
fi
if [ ! -e /var/log/btmp ]; then
        install -m0600 -o root -g utmp /dev/null /var/log/btmp
fi
if [ ! -e /var/log/lastlog ]; then
        install -m0600 -o root -g utmp /dev/null /var/log/lastlog
fi

# HyperVisor often beats Void to the punch
if ! mountpoint -q /tmp/.X11-unix; then
    install -dm1777 /tmp/.X11-unix /tmp/.ICE-unix
fi

rm -f /etc/nologin /forcefsck /forcequotacheck /fastboot