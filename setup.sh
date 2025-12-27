#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
MAIN_SCRIPT_NAME="main.sh" # Ensure this matches actual script name
# Get the absolute path to the directory where this script is running
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
MAIN_SCRIPT_PATH="$SCRIPT_DIR/$MAIN_SCRIPT_NAME"
REAL_USER="$SUDO_USER"

# ==============================================================================
# ROOT CHECK
# ==============================================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] This setup script must be run with sudo.\033[0m"
    exit 1
fi

if [ -z "$REAL_USER" ]; then
    echo -e "\033[0;31m[ERROR] Could not detect the real user. Are you running this from a root shell?\033[0m"
    echo "Please run via 'sudo ./setup.sh' from your normal user account."
    exit 1
fi

# ==============================================================================
# INSTALL DEPENDENCIES
# ==============================================================================
echo -e "\033[1;36m[STEP 1/3] Installing Dependencies...\033[0m"
REQUIRED=("ffmpeg" "pulseaudio-utils" "bluez" "rfkill" "expect" "pulseaudio-module-bluetooth" "bc" "lsof" "psmisc")
if [ -f /etc/debian_version ]; then
    if [ "$EUID" -ne 0 ]; then CMD="sudo apt"; else CMD="apt"; fi
    for pkg in "${REQUIRED[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            if [ "$EUID" -ne 0 ]; then
                sudo DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null
            else
                export DEBIAN_FRONTEND=noninteractive
                apt-get update >/dev/null
                apt-get install -y "$pkg" >/dev/null
            fi
        fi
    done
fi

# ==============================================================================
# CONFIGURE UDEV FOR RFKILL
# ==============================================================================
echo -e "\033[1;36m[STEP 2/3] Configuring permissions for RFKILL...\033[0m"

# Create a udev rule that assigns /dev/rfkill to the 'plugdev' group
# This allows members of 'plugdev' to use rfkill without sudo
cat <<EOF > /etc/udev/rules.d/99-rfkill-permission.rules
KERNEL=="rfkill", GROUP="plugdev", MODE="0664"
EOF

# Ensure the real user is in the plugdev group
if ! groups "$REAL_USER" | grep -q "\bplugdev\b"; then
    echo "Adding user $REAL_USER to 'plugdev' group..."
    usermod -a -G plugdev "$REAL_USER"
else
    echo "User $REAL_USER is already in 'plugdev' group."
fi

# Reload udev rules to apply changes immediately
udevadm control --reload-rules && udevadm trigger
chmod 666 /dev/rfkill
echo -e "\033[0;32m[OK] Udev rules applied. User $REAL_USER can now control Bluetooth power.\033[0m"

# ==============================================================================
# MAIN SCRIPT PRIVILEDGE and CLEANUP
# ==============================================================================
chmod +x $MAIN_SCRIPT_NAME
echo -e "\033[0;32m[OK] Main script is now executable.\033[0m"

# ==============================================================================
# 4. CRONTAB SETUP
# ==============================================================================
echo -e "\033[1;36m[STEP 3/3] Boot Configuration\033[0m"

if [ ! -f "$MAIN_SCRIPT_PATH" ]; then
    echo -e "\033[0;31m[WARNING] Could not find $MAIN_SCRIPT_NAME in $SCRIPT_DIR.\033[0m"
    echo "Skipping Crontab setup. Please ensure the main script is present."
else
    # Make the main script executable
    chmod +x "$MAIN_SCRIPT_PATH"

    echo "Found main script at: $MAIN_SCRIPT_PATH"
    read -p "Do you want to run this script automatically at startup? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Check if the job already exists to avoid duplicates
        if crontab -u "$REAL_USER" -l 2>/dev/null | grep -q "$MAIN_SCRIPT_PATH"; then
             echo "Entry already exists in crontab."
        else
             # Append the @reboot command to the user's crontab
             # We use a temporary file to safely append
             (crontab -u "$REAL_USER" -l 2>/dev/null; echo "@reboot sleep 10 && $MAIN_SCRIPT_PATH >> $SCRIPT_DIR/bt_audio.log 2>&1") | crontab -u "$REAL_USER" -
             echo -e "\033[0;32m[OK] Crontab updated. The script will run on next boot.\033[0m"
        fi
    else
        echo "Skipping boot configuration."
    fi
fi

echo -e "\n\033[1;32m[SUCCESS] Setup complete!\033[0m"
echo "You may need to log out and back in for group permissions to take effect."
