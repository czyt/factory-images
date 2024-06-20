#!/usr/bin/env bash

echo "copying systemd service define and related scripts"
cp -f ./overlay/usr/lib/systemd/system/* /usr/lib/systemd/system/
cp -f ./overlay/usr/lib/scripts/* /usr/lib/scripts/

echo "copying holomotion theme and wallpapers.."
cp -r ./overlay/usr/share/plymouth/themes/holomotion /usr/share/plymouth/themes/
mkdir -p "/usr/share/backgrounds"
cp "./overlay/usr/share/backgrounds/holomotion01.jpeg" /usr/share/backgrounds/holomotion01.jpeg


for sc in ./postscripts/*.sh; do
    if [ -f "$sc" ]; then
        source "$sc"
    fi
done
echo "apply quick setup"
quick-setup