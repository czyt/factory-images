#!/bin/env bash

exec &> /var/log/firstboot-options-apply.log

target_user="holomotion"
default_desktop_dir="/home/holomotion/桌面"

# Function to get the D-Bus session address for a specific user
get_dbus_session_address() {
    local user=$1
    # shellcheck disable=SC2155
    local user_id=$(id -u "$user")
    local dbus_address_file="/run/user/$user_id/dbus-session"

    # If the D-Bus address file exists, read the address from it
    if [ -f "$dbus_address_file" ]; then
        # shellcheck disable=SC2155
        export DBUS_SESSION_BUS_ADDRESS=$(cat "$dbus_address_file")
    else
        # Otherwise, start a new D-Bus session for the user and save the address
        # shellcheck disable=SC2046
        eval $(sudo -u "$user" dbus-launch --sh-syntax)
        echo "$DBUS_SESSION_BUS_ADDRESS" > "$dbus_address_file"
    fi
}

# Get the D-Bus session address for the target user
get_dbus_session_address $target_user

echo "apply power options"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.session idle-delay 0
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.screensaver lock-enabled false

echo "enable keyboard"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true

echo "adjust ibus ime"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.freedesktop.ibus.general engines-order "[ 'pinyin','xkb:us::eng']"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.freedesktop.ibus.general preload-engines "['pinyin']"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('ibus', 'libpinyin'), ('ibus', 'pinyin')]"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.input-sources current 2
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" ibus restart


if [ -f "/usr/share/backgrounds/holomotion01.jpeg" ];then
    echo "set wallpaper"
    sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/holomotion01.jpeg'
fi

user_desktop_dir=$(sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xdg-user-dir DESKTOP || echo "$default_desktop_dir")

holomotion_desktop_file="/home/$target_user/.config/autostart/HoloMotion.desktop"
if [ -f $holomotion_desktop_file ]; then
    echo "create Holomotion desktop file.."
    cp -f $holomotion_desktop_file "$user_desktop_dir"
    chown $target_user:$target_user "$user_desktop_dir/HoloMotion.desktop"
    chmod a+x "$user_desktop_dir/HoloMotion.desktop"
    sudo -u holomotion env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gio set "$user_desktop_dir/HoloMotion.desktop" "metadata::trusted" true
fi

training_assist_desktop_file="/home/$target_user/.config/autostart/train_assist_client.desktop"
if [ -f $training_assist_desktop_file ]; then
    echo "create training assist desktop file.."
    cp -f $training_assist_desktop_file "$user_desktop_dir"
    chown $target_user:$target_user "$user_desktop_dir/train_assist_client.desktop"
    chmod a+x "$user_desktop_dir/train_assist_client.desktop"
    sudo -u holomotion env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gio set "$user_desktop_dir/train_assist_client.desktop" "metadata::trusted" true
fi


count_file="/home/$target_user/.config/firstboot-run-counter"
if [ ! -f "$count_file" ]; then
    echo 0 > "$count_file"
fi
count=$(cat "$count_file")
count=$((count + 1))
if [ $count -ge 6 ];then
    systemctl disable firstboot-options-apply
    rm -rf "$count_file"
fi
echo $count > "$count_file"