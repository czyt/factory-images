# shellcheck shell=bash
function install_training_assist() {

    echo "pre-install training_assist "
    installerRepo="https://e.coding.net/g-hvab4800/train_assist/client_versions.git"
    VERSION_REGEX_RELEASE="^[0-9]+\.[0-9]+\.[0-9]+-[0-9]{8}$"

    install_dir="/home/holomotion/local/bin"
    ntsport_dir="$install_dir/ntsports"
    program_dir="$ntsport_dir/client_versions"

    startup_bin="$install_dir/train_assist_client"
    startup_icon="$ntsport_dir/train_assist_for_linux.png"

    startup_src="$program_dir/train_assist_for_linux.sh"
    startup_app="$ntsport_dir/train_assist_for_linux.sh"

    install_src="$program_dir/train_assist_installer.sh"
    install_bin="$install_dir/train_assist_installer"
    install_app="$ntsport_dir/train_assist_installer.sh"


    /bin/bash -c "[ -d $ntsport_dir ] || mkdir -p $ntsport_dir"

    cat <<-EOF >"${ntsport_dir}/branch.txt"
    release
EOF
    git clone $installerRepo $program_dir
    git config --global --add safe.directory $program_dir
    /bin/bash -c "sudo -u holomotion git config --global --add safe.directory ${program_dir}"


    # get latest relase tag version
    latest_version=$(/bin/bash -c "git -C $program_dir ls-remote --tags --refs origin | awk -F/ '{print \$3}' | grep -E '$VERSION_REGEX_RELEASE' | sort -t '-' -k 1,1V -k 2,2n | awk 'END{print}'")
    if echo "$latest_version" | grep -qE "$VERSION_REGEX_RELEASE"; then
        echo "got latest relase version $latest_version"
         git -C $program_dir reset --hard "$latest_version"
    fi
    echo "check file $install_src "
    if [ -f "${install_src}" ]; then
        echo "copying ${install_src} to ${install_app} in "
         cp -f "${install_src}" "${install_app}" >/dev/null 2>&1 || true
        echo "create soft link for $install_app  with target $install_bin"
         ln -s -f "$install_app" "$install_bin" >/dev/null 2>&1 || true
         chmod +x "$install_app" >/dev/null 2>&1 || true
    fi

    echo "check file $startup_src "
    if [ -f "${startup_src}" ];then
        echo "copying ${startup_src} to ${startup_app} in "
         cp -f "${startup_src}" "${startup_app}" >/dev/null 2>&1 || true
        echo "create soft link for $startup_app  with target $startup_bin"
         ln -s -f "$startup_app" "$startup_bin" >/dev/null 2>&1 || true
         chmod +x "$startup_app" >/dev/null 2>&1 || true
    fi

    mkdir -p "/usr/share/applications"
    # create desktop
    cat <<-EOF >"/usr/share/applications/train_assist_client.desktop"
    [Desktop Entry]
    Type=Application
    Name=训练机客户端
    GenericName=训练机客户端
    Comment=训练机客户端
    Exec="$startup_app" %f
    Icon=$startup_icon
    Terminal=true
    Categories=X-Application;
EOF

    # create startup run
    mkdir -p "/home/holomotion/.config/autostart"
    cat <<-EOF >"/home/holomotion/.config/autostart/train_assist_client.desktop"
    [Desktop Entry]
    Type=Application
    Name=训练机客户端
    GenericName=训练机客户端
    Comment=训练机客户端
    Exec="$startup_app" %f
    Icon=$startup_icon
    Terminal=true
    Categories=X-Application;
EOF

    /bin/bash -c "chown -R holomotion:holomotion /home/holomotion"

    echo "pre-install training assist completed"

    return 0
}