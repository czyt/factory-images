#!/usr/bin/env bash

if [ -z "$SUDO_USER" ]; then
    echo "This script must be run with sudo."
    exit 1
fi

set -e  # 在脚本执行过程中遇到错误时停止执行

function build_image() {
    board="$1"
    addon=$2
    local dis_relese_url="https://api.github.com/repos/Joshua-Riek/ubuntu-rockchip/releases/latest"
    local image_latest_tag=$(curl -s "$dis_relese_url" | grep -m 1 '"tag_name":' | awk -F '"' '{print $4}')
    
    if [ -n "$image_latest_tag" ]; then
        echo "The ubuntu-rockchip latest release tag: $image_latest_tag"
        local image_download_url="https://github.com/Joshua-Riek/ubuntu-rockchip/releases/download/$image_latest_tag/ubuntu-24.04-preinstalled-desktop-arm64-$board.img.xz"
        local image_save_name="ubuntu-24.04-preinstalled-desktop-arm64-$board.img.xz"

        if [ ! -d dist ]; then
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
        if [ -f "$image_save_name" ]; then
            echo "Image exists, unpacking it..."
           
            MOUNT_POINT="/mnt/ubuntu-img"
            IMG_PATH="ubuntu-24.04-preinstalled-desktop-arm64-$board.img"

            if [ ! -f "$IMG_PATH" ]; then
                xz -d "$image_save_name"
            fi

            mkdir -p $MOUNT_POINT/{dev,proc,sys,boot,tmp}

            for i in {0..7}; do
                if [ ! -b "/dev/loop$i" ]; then
                    mknod "/dev/loop$i" b 7 "$i"
                    chmod 660 "/dev/loop$i"
                fi
            done

            if [ ! -c /dev/loop-control ]; then
                mknod /dev/loop-control c 10 237
                chmod 660 /dev/loop-control
            fi

        
            LOOP_DEVICE=$(losetup -fP --show "$IMG_PATH")
        
            partprobe "$LOOP_DEVICE"

            ROOT_PARTITION=$(find /dev -type b -name "$(basename ${LOOP_DEVICE})p*" | tail -n 1)
            
            if [ -z "$ROOT_PARTITION" ]; then
                echo "No partitions found in the loop device"
                losetup -d "$LOOP_DEVICE"
                exit 1
            fi

            mount "$ROOT_PARTITION" $MOUNT_POINT

            for dir in dev proc sys; do
                mount --bind /$dir $MOUNT_POINT/$dir
            done

            echo "Image mounted. Returning to previous directory..."
            cd - || unmount_all

            echo "Copying QEMU binary..."
            apt-get install qemu-user-static binfmt-support -y
            
            if [ ! -f $MOUNT_POINT/usr/bin/qemu-aarch64-static ]; then
                cp /usr/bin/qemu-aarch64-static $MOUNT_POINT/usr/bin/qemu-aarch64-static
            fi

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
            img_file="images/ubuntu-24.04-preinstalled-desktop-arm64-$board.img"
            if [ -n "$addon" ]; then
                img_file="images/ubuntu-24.04-preinstalled-desktop-arm64-$board-with-$addon.img"
            fi
            mv "dist/$IMG_PATH" "$img_file"
            check_and_handle_image_split  "$img_file"
        fi
    fi
}

function check_and_handle_image_split(){
    img_file=$1
    cd images
    echo -e "\nCompressing $(basename "${img_file}.xz")\n"
    xz -6 --force --keep --quiet --threads=0 "${img_file}"
    rm -f "${img_file}"
    echo "check whether to process img.xz"
    COMPRESSED_FILE="${img_file}.xz"
    FILE_SIZE=$(stat -c%s "${COMPRESSED_FILE}")
    MAX_SIZE=$((2 * 1024 * 1024 * 1024))

    if [ ${FILE_SIZE} -gt ${MAX_SIZE} ]; then
        echo "the compressed file is large,begin to split img to parts"
        SPLIT_SIZE=2000M
        split -b $SPLIT_SIZE --numeric-suffixes=1 -d "${COMPRESSED_FILE}" "${COMPRESSED_FILE}.part"
        for part in "$(basename "${COMPRESSED_FILE}").part"*; do
            sha256sum "$part" > "$part.sha256"
        done
        rm -rf "${COMPRESSED_FILE}"
    else
        echo "no need to process compressed image,calculate the checksum."
        sha256sum "$(basename "${img_file}.xz")" > "$(basename "${img_file}.xz.sha256")"
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
    unmount_point /mnt/ubuntu-img/boot

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

board="$1"
addon="$2"

build_image "$board" "$addon"