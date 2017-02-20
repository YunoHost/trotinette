
KERNEL_REPO="https://github.com/AmitAronovitch/qemu-rpi-kernel"
KERNEL_REPO_NAME=$(basename $KERNEL_REPO)

KERNEL="kernel-qemu-4.4.34-jessie"

IMAGE_TO_TEST="2017-01-11-raspbian-jessie-lite-ready"
IMAGE="2017-01-11-raspbian-jessie-lite-test"

function tweak_image()
{

    # Start by mounting the image..
    kpartx -av ${IMAGE}.img
    sleep 1
    mkdir -p /mnt/loop0p2
    mount /dev/mapper/loop0p2 /mnt/loop0p2

    # Need to disable the stuff in ld.so.preload...
    sed -i 's@^@#@g' /mnt/loop0p2/etc/ld.so.preload
    # Need to disable also the mounting of /dev/mm0blockthing
    sed -i 's@/dev@#/dev@g' /mnt/loop0p2/etc/fstab

    # Umount image
    umount /mnt/loop0p2
    kpartx -d ${IMAGE}.img

    # Exand image size
    qemu-img resize $IMAGE.img +4G
    
    sleep 1

}


# Copy image to file dedicated to test
cp ${IMAGE_TO_TEST}.img ${IMAGE}.img

# Tweak the test image (disable ipv6, expand)
tweak_image

# Disable audio
export QEMU_AUDIO_DRV=none

# Launch raspi (with display in a X window)
qemu-system-arm \
    -kernel ./qemu-rpi-kernel/$KERNEL \
    -cpu arm1176 \
    -m 256 \
    -M versatilepb \
    -no-reboot \
    -serial pty \
    -append "root=/dev/sda2 panic=1 rootfstype=ext4 rw" \
    -hda ${IMAGE}.img \
    -net nic -net user,hostfwd=tcp::2200-:22

# Relaunch after reboot
qemu-system-arm \
    -kernel ./qemu-rpi-kernel/$KERNEL \
    -cpu arm1176 \
    -m 256 \
    -M versatilepb \
    -no-reboot \
    -serial pty \
    -append "root=/dev/sda2 panic=1 rootfstype=ext4 rw" \
    -hda ${IMAGE}.img \
    -net nic -net user,hostfwd=tcp::2200-:22
