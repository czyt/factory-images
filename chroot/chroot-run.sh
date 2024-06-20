#!/usr/bin/env bash

addon=$1
echo "source functions"
for sc in /tmp/postscripts/*.sh; do
    if [ -f "$sc" ]; then
        echo "import functions in $sc"
        source "$sc"
    fi
done

echo "apply quick setup"
quick_setup

echo "check addon setting"
if [ -z "$addon" ]; then
    echo "no addon provided,script exit"
    exit 0
fi

echo "addon provided,start to process |$addon|"
case $addon in
holomotion)
    install_holomotion
;;
mongodb)
    install_mongodb
;;
trainging)
    install_training_assist
;;
esac

