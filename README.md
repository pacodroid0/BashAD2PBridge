# BashAD2PBridge
Script for bridging AD2P bluetooth audio strem on an network stream via bash commands.
This script is designed to automate Bluetooth device pairing and management on Linux systems using bluetoothctl1 and route the audio stream to a network socket.
The script initializes a background pairing agent with the following capabilities:
- Automated Environment Setup: It disables existing agents before initializing a new KeyboardDisplay agent and setting it as the default3.
- Controller Configuration: Automatically ensures the Bluetooth controller is powered on and set to both discoverable and pairable modes4.Interaction Automation: Uses expect to monitor for "yes/no" prompts, "Confirm passkey" requests, and "Authorize service" messages, automatically replying with "yes"5.
- Automatic Trusting: Detects successful connections via regex, extracts the device MAC address, and issues a trust command to ensure the device can reconnect in the future without intervention6.

# Security Note
This script automatically trusts and authorizes Bluetooth devices that attempt to connect14. It is intended for controlled environments where manual pairing interaction is impossible
