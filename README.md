# Trotinette

 Automatically create Yunohost image for Raspberry Pi 

## What does it do ?

Qemu is used to virtualize a raspberry pi.

Launching this script will :
- install the dependencies if needed
- fetch the right kernels and image if needed
- tweak the image
- launch a virtual raspberry pi
- add space to image (needed for update/upgrade)
- install yunohost (and perform some dirty hack to work around lack of ipv6 inside the virtual RPi)
- untweak / clean the image to be ready for deployment

## To do

- Test the firstboot stuff
