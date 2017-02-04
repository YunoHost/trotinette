#!/bin/bash

###############################################################################

readonly KERNEL_REPO="https://github.com/AmitAronovitch/qemu-rpi-kernel"
readonly KERNEL_REPO_NAME=$(basename $KERNEL_REPO)

readonly KERNEL="kernel-qemu-4.4.34-jessie"

readonly IMAGE_LINK="http://vx2-downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2017-01-10/2017-01-11-raspbian-jessie-lite.zip"
readonly IMAGE=$(basename $IMAGE_LINK | cut -d'.' -f1)

###############################################################################

function install_dependencies()
{
    command -v qemu-system-arm > /dev/null 2>&1 || {
        echo -e "\n Installing dependencies ... \n";
        apt-get install -y qemu-system-arm kpartx unzip; }
}

###############################################################################

function fetch_kernels()
{

    # Clone repo if it's not already there
    if [ ! -d "$KERNEL_REPO_NAME" ];
    then
        echo -e "\n Fetching kernels ...\n"
        git clone $KERNEL_REPO
    fi
}

###############################################################################

function fetch_image()
{
    if [ ! -f "${IMAGE}.zip" ];
    then
        echo -e "\n Fetching Raspbian image ...\n"
        #rm -f ${IMAGE}.zip
        wget -q --show-progress $IMAGE_LINK
    fi
    if [ ! -f "${IMAGE}.img" ];
    then
        unzip ${IMAGE}.zip
        echo -e "\n Tweaking image ...\n"
        tweak_image
    fi
}

###############################################################################

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
    # Start ssh at boot
    touch /mnt/loop0p2/boot/ssh
    # Allow root login on ssh with password
    #sed -i '0,/without-password/s/without-password/yes/g' /mnt/loop0p2/etc/ssh/sshd_config
    # Define root password (will be prompted during the script)
    #sed -i '1d' /mnt/loop0p2/etc/shadow
    #echo "root:$(mkpasswd -m sha-512 -S $(< /dev/urandom tr -dc A-Za-z0-9 | head -c15)):17130:0:99999:7:::" >> /mnt/loop0p2/etc/shadow

    # Generate a ssh key to be used by this script to easily access machine
    mkdir -p /mnt/loop0p2/root/.ssh
    generate_ssh_key >/dev/null 2>&1
    cat .ssh/trotinette.pub >> /mnt/loop0p2/root/.ssh/authorized_keys

    # Umount image
    umount /mnt/loop0p2
    kpartx -d $IMAGE.img

    # Exand image size
    qemu-img resize $IMAGE.img +1G
}

function untweak_image()
{
    # Start by mounting the image..
    kpartx -av ${IMAGE}.img
    sleep 1
    mkdir -p /mnt/loop0p2
    mount /dev/mapper/loop0p2 /mnt/loop0p2


    # Revert the dirty ipv6 hack
    sed -i 's/#listen \[/listen \[/g' /mnt/loop0p2/etc/nginx/sites-available/default
    sed -i 's/::\nlisten = */::/g'    /mnt/loop0p2/etc/dovecot/dovecot.conf
    sed -i 's/#listen \[/listen \[/g' /mnt/loop0p2/usr/share/yunohost/templates/nginx/plain/yunohost_admin.conf

    # Re-enable stuff in ld.so.preload...
    sed -i 's@#@ @g' /mnt/loop0p2/etc/ld.so.preloa
    # Re-enable mounting of /dev/mm0blockthing
    sed -i 's@#/dev@/dev@g' /mnt/loop0p2/etc/fstab
    # Allow root login on ssh with password
    sed -i '0,/without-password/s/without-password/yes/g' /mnt/loop0p2/etc/ssh/sshd_config
    # Define root password as 'yunohost'
    sed -i '1d' /mnt/loop0p2/etc/shadow
    echo "root:$(echo "yunohost" | mkpasswd -m sha-512 -s):17130:0:99999:7:::" >> /mnt/loop0p2/etc/shadow

    # TODO : shrink back rootfs ?

    # Remove ssh key
    rm /mnt/loop0p2/root/.ssh/authorized_keys

	# Delete SSH keys
	rm -f /mnt/loop0p2/etc/ssh/ssh_host_*

    # Remove logs
	find /mnt/loop0p2/var/log -type f -exec rm {} \;

    # Umount image
    umount /mnt/loop0p2
    kpartx -d $IMAGE.img
}



###############################################################################

function generate_ssh_key()
{
    mkdir -p ./.ssh
    chmod 700 ./.ssh
    rm -f ./.ssh/trotinette
    ssh-keygen -t rsa -b 4096 -C "trotinette@yunohost.org" -N "" -f ./.ssh/trotinette
}

###############################################################################

function poweroff_virtual_pi()
{
    if [ `ps -ef | grep qemu | wc -l` -ge "2" ];
    then
        echo -e "\n Powering off currently running virtual pi. \n"
        ssh -p 2200 -i ./.ssh/trotinette root@127.0.0.1 "poweroff"
        sleep 30
    fi
}

function launch_virtual_pi()
{
    if [ `ps -ef | grep qemu | wc -l` -ge "2" ];
    then
        echo -e "\n Virtual pi already running ! Aborting ! \n"
        exit 1
    else

        echo -e "\n Launching virtual pi ... \n"

        # Disable audio (redo each time you open a session..)
        export QEMU_AUDIO_DRV=none

        # Launch raspi (redo each time you need to..)
        qemu-system-arm \
            -kernel ./qemu-rpi-kernel/$KERNEL \
            -cpu arm1176 \
            -m 256 \
            -M versatilepb \
            -no-reboot \
            -display none \
            -daemonize \
            -serial pty \
            -append "root=/dev/sda2 panic=1 rootfstype=ext4 rw" \
            -hda $IMAGE.img \
            -net nic -net user,hostfwd=tcp::2200-:22

        # Make sure to not have a conflicting old ECDSA host key
        ssh-keygen -f "/root/.ssh/known_hosts" -R [127.0.0.1]:2200

        # Wait to be sure pi is fully up
        echo -e "\n Waiting for virtual pi to be fully up ... \n"

        sleep 5

        if [ `ps -ef | grep qemu | wc -l` -le "1" ];
        then
            echo -e "\n qemu crashed ? Aborting ! \n"
            exit 1
        fi

        sleep 30

        # Add the new ECDSA host key
        ssh-keyscan -H -p 2200 127.0.0.1 >> ~/.ssh/known_hosts

        sleep 20

        # Add the new ECDSA host key
        ssh-keyscan -H -p 2200 127.0.0.1 >> ~/.ssh/known_hosts
    fi
}

###############################################################################

function run_on_virtual_pi()
{
    local function_to_run=$1
    local command_="$(typeset -f $function_to_run); $function_to_run;"

    echo -e "\n Running function $function_to_run on virtual pi ... \n"
    echo -e "\n Command : \n $command_ \n"

    ssh -p 2200 -i ./.ssh/trotinette root@127.0.0.1 "$command_"
}

function pi_resize_sda_step1()
{
    SDA2_BEGIN=`fdisk -l | grep /dev/sda2 | awk '{print $2}'`
    (echo d; echo 2; echo n; echo p; echo 2; echo $SDA2_BEGIN; echo; echo w) | fdisk /dev/sda
}
function pi_resize_sda_step2()
{
    resize2fs /dev/sda2
    fdisk -l | grep sda
}

function pi_upgrade()
{
    apt-get update && apt-get upgrade -y && apt-get install rpi-update
    # We don't do the rpi-update because it's only to have bleeding-edge stuff
    # The dist-upgrade already update the firmware (though it's not the most up
    # to date, but it's good enough)
}

function pi_install_yunohost()
{

    # Dirty hack to work around lack of ipv6 for nginx

    apt-get install -y nginx nginx-extras
    echo -e "\n Applying dirty workaround hack on nginx to disable ipv6 ... \n"
    sed -i 's/listen \[/#listen \[/g' /etc/nginx/sites-available/default
    service nginx start
    apt-get install -y nginx nginx-extras

    # Dirty hack to work around lack of ipv6 for dovecot

    apt-get install -y dovecot-core dovecot-ldap dovecot-lmtpd dovecot-managesieved dovecot-antispam
    echo -e "\n Applying dirty workaround hack on dovecot to disable ipv6 ... \n"
    sed -i 's/::$/::\nlisten = */g' /etc/dovecot/dovecot.conf
    service dovecot start
    apt-get install -y dovecot-core dovecot-ldap dovecot-lmtpd
    dovecot-managesieved dovecot-antispam

    # FIXME : add conf variable for install script source and branch to use

    # Launch actual yunohost install
    mkdir /tmp/install_script
    cd /tmp/install_script
    wget https://raw.githubusercontent.com/YunoHost/install_script/4b16d1d12b435fd1b43cbd2302ea85850a22d65b/install_yunohost
    chmod +x install_yunohost
    touch /var/log/yunohost-installation.log
    tail -f /var/log/yunohost-installation.log &
    ./install_yunohost -a -d testing

    # Dirty hack again to work around lack of ipv6 for nginx - in yunohost's templates
    echo -e "\n Applying dirty workaround hack on yunohost/nginx to disable ipv6 ... \n"
    sed -i 's/listen \[/#listen \[/g' /usr/share/yunohost/templates/nginx/plain/yunohost_admin.conf

    # Relaunch configuration ?
    ./install_yunohost -a -d testing

}

###############################################################################

function main()
{
    poweroff_virtual_pi

    install_dependencies
    fetch_kernels
    fetch_image

    launch_virtual_pi

    run_on_virtual_pi pi_resize_sda_step1
    poweroff_virtual_pi
    launch_virtual_pi
    run_on_virtual_pi pi_resize_sda_step2

    run_on_virtual_pi pi_upgrade
    run_on_virtual_pi pi_install_yunohost

    poweroff_virtual_pi

    untweak_image
}

main



