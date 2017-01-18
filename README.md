# Trotinette

Automatically install Yunohost on virtual Raspberry Pi

## What does it do ?

Qemu is used to virtualize a raspberry pi.

Launching this script will :
- install the dependencies if needed
- fetch the right kernels and image if needed
- automatically launch a virtual raspberry pi
- resize image to ~3.2 Go (neede for next steps)
- automatically install yunohost (and perform some dirty hack to work around lack of ipv6 inside the virtual RPi)

## To do

- Check that the resulting image can actually be used on a real Raspberry Pi
- Prepare the image to be used in real life
    - Shrink image size to minimum needed
    - Make sure ssh is launched at boot and user can log as root ?
    - Undo the dirty hack (except to have ipv6 in real life)
    - Undo the tweak of ld.so.preload and /etc/fstab
    - Clear logs and ssh keys
    - rpi-update might not be needed after all (it's only for bleeding-edge firmware, apt-get upgrade also upgrades it though less recent). That would simplify the procedure to have one reboot less.
