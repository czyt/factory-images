#!/usr/bin/env bash

function prepare_base_img(){
    device="$1"
    local dis_relese_url="https://api.github.com/repos/Joshua-Riek/ubuntu-rockchip/releases/latest"
    local image_latest_tag=$(curl -s "$dis_relese_url" | grep -m 1 '"tag_name":' | awk -F '"' '{print $4}')
    # Check if latest_tag is null or empty
    if [ -n "$image_latest_tag" ]; then
        echo "the ubuntu-rockchip latest release tag: $image_latest_tag"
        image_download_url="https://fastgit.czyt.tech/https://github.com/Joshua-Riek/ubuntu-rockchip/releases/download/$image_latest_tag/ubuntu-24.04-preinstalled-desktop-arm64-$device.img.xz"
        mkdir dist || echo "dist dir already exist."
        cd dist||exit 0
        [ -f "base.img.xz" ] || wget "$image_download_url" -O base.img.xz
        echo "check the image exist or not"
        if [ -f "base.img.xz" ];then
            echo "image  exist,unpack it"
            xz -d base.img.xz

            MOUNT_POINT="/mnt/ubuntu-img"

            local IMG_PATH="ubuntu-24.04-preinstalled-server-arm64-$device.img"
            mkdir -p $MOUNT_POINT/{dev,proc,sys,boot,usr,tmp}
            losetup -P /dev/loop0 "$IMG_PATH"
            mount /dev/loop0p2 $MOUNT_POINT
            for dir in dev proc sys usr tmp; do
                mount --bind /$dir $MOUNT_POINT/$dir
            done

            echo "copy qemu binary..."
            apt-get install qemu-user-static -y
            cp /usr/bin/qemu-aarch64-static $MOUNT_POINT/usr/bin/
             
            echo "copying systemd service define and related scripts"
            cp -f ./overlay/usr/lib/systemd/system/* $MOUNT_POINT/usr/lib/systemd/system/
            cp -f ./overlay/usr/lib/scripts/* $MOUNT_POINT/usr/lib/scripts/

            echo "copying holomotion theme and wallpapers.."
            cp -r ./overlay/usr/share/plymouth/themes/holomotion $MOUNT_POINT/usr/share/plymouth/themes/
            mkdir -p "$MOUNT_POINT/usr/share/backgrounds"
            cp "./overlay/usr/share/backgrounds/holomotion01.jpeg" $MOUNT_POINT/usr/share/backgrounds/holomotion01.jpeg
            
            echo "copying user scripts to the mount fs"
            mkdir -p $MOUNT_POINT/tmp
            cp -r "./postscripts"  $MOUNT_POINT/tmp/

            chroot /mnt/ubuntu-img /usr/bin/qemu-aarch64-static /bin/bash <<EOF
            for script in ./postscripts/*.sh; do
                if [ -f "$script" ]; then
                    source "$script"
                fi
            done
             echo "apply quick setup"
            quick-setup

EOF

            unmount_all
           
        fi
       
    fi
}

function unmount_point() {
    if mountpoint -q "$1"; then
        echo "Unmounting $1"
        sudo umount "$1"
    fi
}


function unmount_all(){
    unmount_point /mnt/ubuntu-img/dev/pts
    unmount_point /mnt/ubuntu-img/dev
    unmount_point /mnt/ubuntu-img/proc
    unmount_point /mnt/ubuntu-img/sys

    # Unmount the primary mount point
    unmount_point /mnt/ubuntu-img

    # Detach all associated loop devices
    for loop_device in $(losetup -l | awk '{if(NR>1)print $1}'); do
        # Find all mounts associated with this loop device and unmount them
        for assoc_mount in $(findmnt -nlo TARGET -S "$loop_device"); do
            unmount_point "$assoc_mount"
        done

        # Detach the loop device
        echo "Detaching $loop_device"
        sudo losetup -d "$loop_device"
    done

    echo "All loop devices have been detached and mount points unmounted."
}


prepare_base_img "orangepi-5-plus"