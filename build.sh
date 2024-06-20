#!/usr/bin/env bash

if [ -z "$SUDO_USER" ]; then
    echo "This script must be run with sudo."
    exit 1
fi

set -e  # 在脚本执行过程中遇到错误时停止执行

function setup_mountpoint() {
    local mountpoint="$1"

    if [ ! -c /dev/mem ]; then
        mknod -m 660 /dev/mem c 1 1
        chown root:kmem /dev/mem
    fi

    mount dev-live -t devtmpfs "$mountpoint/dev"
    mount devpts-live -t devpts -o nodev,nosuid "$mountpoint/dev/pts"
    mount proc-live -t proc "$mountpoint/proc"
    mount sysfs-live -t sysfs "$mountpoint/sys"
    mount securityfs -t securityfs "$mountpoint/sys/kernel/security"
    # Provide more up to date apparmor features, matching target kernel
    # cgroup2 mount for LP: 1944004
    mount -t cgroup2 none "$mountpoint/sys/fs/cgroup"
    mount -t tmpfs none "$mountpoint/tmp"
    mount -t tmpfs none "$mountpoint/var/lib/apt/lists"
    mount -t tmpfs none "$mountpoint/var/cache/apt"
    mv "$mountpoint/etc/resolv.conf" resolv.conf.tmp
    cp /etc/resolv.conf "$mountpoint/etc/resolv.conf"
    mv "$mountpoint/etc/nsswitch.conf" nsswitch.conf.tmp
    sed 's/systemd//g' nsswitch.conf.tmp > "$mountpoint/etc/nsswitch.conf"
}

function teardown_mountpoint() {
    # Reverse the operations from setup_mountpoint
    local mountpoint
    mountpoint=$(realpath "$1")

    # ensure we have exactly one trailing slash, and escape all slashes for awk
    mountpoint_match=$(echo "$mountpoint" | sed -e 's,/$,,; s,/,\\/,g;')'\/'
    # sort -r ensures that deeper mountpoints are unmounted first
    awk </proc/self/mounts "\$2 ~ /$mountpoint_match/ { print \$2 }" | LC_ALL=C sort -r | while IFS= read -r submount; do
        mount --make-private "$submount"
        umount "$submount"
    done
    mv resolv.conf.tmp "$mountpoint/etc/resolv.conf"
    mv nsswitch.conf.tmp "$mountpoint/etc/nsswitch.conf"
}

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
            wget "$image_download_url" -O "$image_save_name"> /dev/null
        fi

        echo "Check if the image exists"
        if [ -f "$image_save_name" ]; then
            echo "Image exists, unpacking it..."

            MOUNT_POINT="/mnt/ubuntu-img"
            IMG_PATH="ubuntu-24.04-preinstalled-desktop-arm64-$board.img"

            if [ ! -f "$IMG_PATH" ]; then
                xz -d "$image_save_name"
            fi

            mkdir -p $MOUNT_POINT

            LOOP_DEVICE=$(losetup -fP --show "$IMG_PATH")
            partprobe "$LOOP_DEVICE"

            ROOT_PARTITION=$(lsblk -lno NAME "$LOOP_DEVICE" | grep -E "^$(basename "$LOOP_DEVICE")p.*" | head -n 1 | sed 's/^/\/dev\//')

            if [ -z "$ROOT_PARTITION" ]; then
                echo "No partitions found in the loop device"
                losetup -d "$LOOP_DEVICE"
                exit 1
            fi

            mount "$ROOT_PARTITION" $MOUNT_POINT
            setup_mountpoint $MOUNT_POINT

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

            echo "Copying /etc/resolv.conf into chroot environment..."
            cp /etc/resolv.conf $MOUNT_POINT/etc/resolv.conf

            echo "Entering chroot environment to execute chroot-run.sh..."
            chroot $MOUNT_POINT /usr/bin/qemu-aarch64-static /bin/bash /tmp/chroot-run.sh "$addon"

            teardown_mountpoint $MOUNT_POINT

            mkdir -p ./images
            img_file="./images/ubuntu-24.04-preinstalled-desktop-arm64-$board.img"
            if [ -n "$addon" ];then
                img_file="./images/ubuntu-24.04-preinstalled-desktop-arm64-$board-with-$addon.img"
            fi
            echo "moving $IMG_PATH to $img_file "
            mv "$IMG_PATH" "$img_file"
            check_and_handle_image_split "$img_file"
        fi
    fi
}

function check_and_handle_image_split(){
    img_file=$1
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
    MOUNT_POINT="/mnt/ubuntu-img"

    for mount_dir in $MOUNT_POINT/dev/pts $MOUNT_POINT/dev $MOUNT_POINT/proc $MOUNT_POINT/sys $MOUNT_POINT/boot; do
        unmount_point "$mount_dir"
    done

    unmount_point $MOUNT_POINT
}

board="$1"
addon="$2"

build_image "$board" "$addon"
