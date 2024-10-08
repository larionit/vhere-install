#!/bin/bash

### ======== Settings ======== ###

# Specify url, file name and path for the .service file
vhclient_service_url=https://www.virtualhere.com/sites/default/files/usbclient/scripts/virtualhereclient.service
vhclient_service=$(basename $vhclient_service_url)
vhclient_service_path=/etc/systemd/system

# Specify the URL, filename and path for the executable file
vhclient_bin_url=https://www.virtualhere.com/sites/default/files/usbclient/vhclientx86_64
vhclient_bin=$(basename $vhclient_bin_url)
vhclient_bin_path=/usr/sbin

### ======== Settings ======== ###

### -------- Functions -------- ###

# Privilege escalation function
function elevate {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run with superuser privileges. Trying to elevate privileges with sudo."
        exec sudo bash "$0" "$@"
        exit 1
    fi
}

# Function for logging (when called, it outputs a message to the console containing date, time and the text passed in the first argument)
function log {
    echo
    echo "$(date '+%Y-%m-%d %H:%M:%S') -> $1"
    echo
}

# Function to continue script execution after a reboot
function before_reboot {
    # Add this script to .bashrc so that it runs immediately after the user logs in.
    echo "bash ${script_path}" >> /home/$script_was_started_by/.bashrc

    # Create a flag file to check if we are resuming from reboot.
    touch $flag_file_resume_after_reboot

    # Print message to console
    clear
    echo
    echo "Требуется перезагрузка"
    echo
    read -p "Нажмите Enter для перезагрузки: "
    echo

    # Reboot
    reboot
}

# Function to disable the launch of this script when a user logs in
function after_reboot {
    # Remove a flag file
    rm $flag_file_resume_after_reboot

    # Remove this script from bashrc
    sed -i "/bash ${script_path_sed}/d" "$bashrc_file"
}

# Function that displays the start message and waits for user confirmation to continue
function message_before_start {
    # Print message to console
    clear
    echo
    echo "Скрипт: $script_name"
    echo
    echo "Лог: $logfile_path"
    echo
    echo "Будут установлены:"
    echo
    echo "${echo_tab} $vhclient_bin"
    echo

    # Wait until the user presses enter
    read -p "Нажмите Enter, чтобы начать: "
}

# Function displaying the final summary of the script execution results
function message_at_the_end {
    # Print message to console
    clear
    echo
    echo "IP: $show_ip"
    echo
    echo "Скрипт: $script_name"
    echo
    echo "Лог: $logfile_path"
    echo
    echo "Установлены:"
    echo
    echo "${echo_tab}VirtualHere Client $vhclient_installed_version"
    echo
    echo "$vhclient_service:"
    echo
    systemctl --no-pager status $vhclient_service | grep Active
    echo
    echo "Список доступных устройств:"
    echo
    echo "${echo_tab}vhclientx86_64 -t "\""LIST"\"""
    echo
    echo "Подключить usb-устройство:"
    echo
    echo "${echo_tab}vhclientx86_64 -t "\""USE,hostname.number"\"""
    echo
    echo "Автоматическое подключение usb-устройста после запуска:"
    echo
    echo "${echo_tab}vhclientx86_64 -t "\""AUTO USE DEVICE PORT,hostname.number"\"""
    echo
    echo "Если "\""Auto Search"\"" отключен или не работает, вы можете добавить сервер вручную:"
    echo
    echo "${echo_tab}vhclientx86_64 -t "\""MANUAL HUB ADD,serverip:7575"\"""
    echo
}

### -------- Functions -------- ###

### -------- Preparation -------- ###

# Define the directory where this script is located
script_dir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Define the name of this script
script_name=$(basename "$0")

# Defining the directory name and script name if the script is launched via a symbolic link located in /usr/local/bin
if [[ "$script_dir" == *"/usr/local/bin"* ]]; then
    real_script_path=$(readlink ${0})
    script_dir="$( cd -- "$(dirname "$real_script_path")" >/dev/null 2>&1 ; pwd -P )"
    script_name=$(basename "$real_script_path")
fi

# Path to this script
script_path="${script_dir}/${script_name}"

# Path to this script with escaped slashes (for sed)
script_path_sed=$(echo "$script_path" | sed 's/\//\\\//g')

# Path to log file
logfile_path="${script_dir}/${script_name%%.*}.log"

# For console output
echo_tab='     '
show_ip=$(hostname -I)

# Set the flag file name and location
flag_file_resume_after_reboot="${script_dir}/resume-after-reboot-${script_name%%.*}"

# Get user name
script_was_started_by=$(logname)

# Path to .bashrc
bashrc_file="/home/${script_was_started_by}/.bashrc"

# Privilege escalation
elevate

# Start logging
exec > >(tee -a "$logfile_path") 2>&1

### -------- Preparation -------- ###

### -------- Script start  -------- ###

# Message to log
log "Script start"

# Output the start message only if there is no flag file
if [ ! -f $flag_file_resume_after_reboot ]; then
    message_before_start
fi

### -------- Script start -------- ###

### -------- Checking for kernel modules -------- ###

# Message to log
log "Checking for kernel modules"

# This section checks if the kernel modules "usbip_core" and "vhci-hcd" are loaded.
# If after manual loading of the modules the check fails,
# it is likely that the script is executed in a system deployed from ubuntu cloud image,
# so install the package "linux-image-extra-virtual", reboot and continue executing this script.

# Loading kernel modules
modprobe usbip-core
modprobe vhci-hcd

# Set the current status of kernel modules in variables
kmod_check_usbip_core=$(lsmod | awk '{print $1}' | grep usbip_core)
kmod_check_vhci_hcd=$(lsmod | awk '{print $1}' | grep vhci_hcd)

# Check usbip_core kernel module is loaded, if no - 
if [[ ! "$kmod_check_usbip_core" == "usbip_core" ]]; then
    apt update && apt install -y linux-image-extra-virtual
    before_reboot
fi

if [[ ! "$kmod_check_vhci_hcd" == "vhci_hcd" ]]; then
    apt update && apt install -y linux-image-extra-virtual
    before_reboot
fi

### -------- Checking for kernel modules -------- ###

### -------- Download and install -------- ###

# Message to log
log "Download and install"

# Download and move to the specified path
curl -fsSL $vhclient_service_url -O
mv $vhclient_service $vhclient_service_path/$vhclient_service

# Download, make it executable and move it to the specified path
curl -fsSL $vhclient_bin_url -O
chmod +x ./$vhclient_bin
mv ./$vhclient_bin $vhclient_bin_path

# Enable service startup on boot and run it
systemctl daemon-reload
systemctl enable $vhclient_service
systemctl start $vhclient_service

# Check which version is installed
vhclient_installed_version=$(vhclientx86_64 -t "HELP" | grep "VirtualHere Client" | awk '{print $3}')

### -------- Download and install -------- ###

### -------- Scrip end -------- ###

# Message to log
log "Scrip end"

# Output the start message only if there is no flag file
if [ -f $flag_file_resume_after_reboot ]; then
    # Disable script launch after user login
    after_reboot

    # Print message to console
    message_at_the_end
fi

### -------- Scrip end -------- ###