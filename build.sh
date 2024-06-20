#!/usr/bin/env bash

set -e  # 在脚本执行过程中遇到错误时停止执行

function prepare_base_img() {
    device="$1"
    addon=$2
    local dis_relese_url="https://api.github.com/repos/Joshua-Riek/ubuntu-rockchip/releases/latest"
    local image_latest_tag=$(curl -s "$dis_relese_url" | grep -m 1 '"tag_name":' | awk -F '"' '{print $4}')
    
    if [ -n "$image_latest_tag" ];then
        echo "The ubuntu-rockchip latest release tag: $image_latest_tag"
        local image_download_url="https://fastgit.czyt.tech/https://github.com/Joshua-Riek/ubuntu-rockchip/releases/download/$image_latest_tag/ubuntu-24.04-preinstalled-desktop-arm64-$device.img.xz"
        local image_save_name="ubuntu-24.04-preinstalled-desktop-arm64-$device.img.xz"

        if [ ! -d dist ];then
            mkdir dist || echo "Dist directory creation failed."
        fi

        cd dist || exit 0

        if [ -f "$image_save_name" ];then
            echo "$image_save_name already exists. Skipping download."
        else
            echo "$image_save_name not found. Downloading..."
            wget "$image_download_url" -O "$image_save_name"
        fi

        echo "Check if the image exists"
        if [ -f "$image_save_name" ];then
            echo "Image exists, unpacking it..."
           
            MOUNT_POINT="/mnt/ubuntu-img"
            IMG_PATH="ubuntu-24.04-preinstalled-desktop-arm64-$device.img"

            if [ ! -f "$IMG_PATH" ];then
                xz -d "$image_save_name"
            fi

            mkdir -p $MOUNT_POINT/{dev,proc,sys,etc,usr,bin,tmp}

            # 创建和检查 loop 设备
            for i in {0..7}; do
                if [ ! -b /dev/loop$i ]; then
                    sudo mknod /dev/loop$i b 7 $i
                    sudo chmod 660 /dev/loop$i
                fi
            done

            if [ ! -c /dev/loop-control ]; then
                sudo mknod /dev/loop-control c 10 237
                sudo chmod 660 /dev/loop-control
            fi

            # 设置 loop 设备
            LOOP_DEVICE=$(losetup -fP --show "$IMG_PATH")
        
            # 确保 loop 设备检测到分区
            partprobe "$LOOP_DEVICE"

            # 获取动态分区名
            ROOT_PARTITION=$(ls ${LOOP_DEVICE}*p* | tail -n 1)  # 假设最后一个分区是根分区
            
            if [ -z "$ROOT_PARTITION" ];then
                echo "No partitions found in the loop device"
                losetup -d "$LOOP_DEVICE"
                exit 1
            fi

            mount "$ROOT_PARTITION" $MOUNT_POINT

            for dir in dev proc sys etc usr bin tmp; do
                mount --bind /$dir $MOUNT_POINT/$dir
            done

            echo "Image mounted. Returning to previous directory..."
            cd - || unmount_all

            echo "Copying QEMU binary..."
            apt-get install qemu-user-static binfmt-support -y
            cp -f /usr/bin/qemu-aarch64-static $MOUNT_POINT/usr/bin/

            echo "Copying systemd service definitions and related scripts..."
            cp -r ./overlay/usr/lib/systemd/system/* $MOUNT_POINT/usr/lib/systemd/system/
            cp -r ./overlay/usr/lib/scripts/* $MOUNT_POINT/usr/lib/

            echo "Copying Holomotion theme and wallpapers..."
            cp -r ./overlay/usr/share/plymouth/themes/holomotion $MOUNT_POINT/usr/share/plymouth/themes/
            mkdir -p "$MOUNT_POINT/usr/share/backgrounds"
            cp "./overlay/usr/share/backgrounds/holomotion01.jpeg" $MOUNT_POINT/usr/share/backgrounds/holomotion01.jpeg

            echo "Copying user scripts to the mounted filesystem..."
            mkdir -p $MOUNT_POINT/tmp
            cp -r "./postscripts" $MOUNT_POINT/tmp/
            cp -f "./chroot/chroot-run.sh" $MOUNT_POINT/tmp/chroot-run.sh

            echo "Entering chroot environment to execute chroot-run.sh..."
            chroot $MOUNT_POINT /usr/bin/qemu-aarch64-static /bin/bash /tmp/chroot-run.sh "$addon"

            unmount_all
            
            mkdir -p images
            if [ -z "$addon" ];then
                mv "dist/$IMG_PATH" "images/ubuntu-24.04-preinstalled-desktop-arm64-$device.img"
            else
                mv "dist/$IMG_PATH" "images/ubuntu-24.04-preinstalled-desktop-arm64-$device-with-$addon.img"
            fi
           
        fi
    fi
}

function unmount_point() {
    if mountpoint -q "$1"; then
        echo "Unmounting $1"
        sudo umount "$1"
    fi
}

function unmount_all() {
    unmount_point /mnt/ubuntu-img/dev/pts
    unmount_point /mnt/ubuntu-img/dev
    unmount_point /mnt/ubuntu-img/proc
    unmount_point /mnt/ubuntu-img/sys
    unmount_point /mnt/ubuntu-img/etc
    unmount_point /mnt/ubuntu-img/usr
    unmount_point /mnt/ubuntu-img/bin

    unmount_point /mnt/ubuntu-img

    for loop_device in $(losetup -l | awk '{if(NR>1)print $1}'); do
        for assoc_mount in $(findmnt -nlo TARGET -S "$loop_device"); do
            unmount_point "$assoc_mount"
        done
        echo "Detaching $loop_device"
        sudo losetup -d "$loop_device"
    done

    echo "All loop devices detached and mount points unmounted."
}

prepare_base_img "orangepi-5-plus" ""