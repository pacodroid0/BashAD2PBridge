# BashA2DPBridge
This script transforms a Linux device (likely a Raspberry Pi or a headless server) into a Bluetooth Audio Receiver and HTTP Streaming Bridge.
- Bluetooth Receiver (A2DP): It initializes the Bluetooth adapter, makes the device discoverable, and uses a background expect script to automatically accept incoming pairing requests and trust devices.
- Audio Routing Bridge: It creates a virtual audio sink (A2DP_Bridge). It automatically detects when a phone connects via Bluetooth and creates a "loopback" module to route the phone's audio into this virtual sink.
- HTTP Audio Server: It uses ffmpeg to capture audio from the virtual sink's monitor and streams it over HTTP on port 8090. This allows you to listen to the Bluetooth audio on a different device via a network stream.
- Codec Transcoding: It offers a menu to select the streaming format: WAV (low latency), OPUS (low bandwidth), or MP3 (compatibility).
- Metadata Dashboard: It queries the D-Bus system to fetch the currently playing track (Artist/Title) and status (Playing/Paused) from the connected Bluetooth device and displays it in the terminal.
- Automated Environment Setup: It disables existing agents before initializing a new KeyboardDisplay agent and setting it as the default3.
- Controller Configuration: Automatically ensures the Bluetooth controller is powered on and set to both discoverable and pairable modes4.
- Interaction Automation: Uses expect to monitor for "yes/no" prompts, "Confirm passkey" requests, and "Authorize service" messages, automatically replying with "yes"5.
- Automatic Trusting: Detects successful connections via regex, extracts the device MAC address, and issues a trust command to ensure the device can reconnect in the future without intervention6.
# Security Note
This script automatically trusts and authorizes Bluetooth devices that attempt to connect14. It is intended for controlled environments where manual pairing interaction is impossible
# Prerequisites
- OS: For automated setup - Debian-based Linux distribution (Ubuntu, Raspberry Pi OS, Debian) or any Linux distro (but the configuration should be perfomed manually).
- Hardware: A device with a working Bluetooth adapter and network connection.
- Permissions: You must have sudo access.
# Installation
- Donwnload and save the 5 .sh files in a local folder.
- Make the setup script executable:
"chmod +x setup.sh"
- Run the setup script as Root
"sudo ./setup.sh"
- The setup will install all the required packages, and prepare the system
- At the end of setup you will be prompted if the script have to be started automatically on boot (via crontab)
# How to Use
- Run the script (manually):
"./main.sh"
- Select Codec: When prompted, choose your audio format:
    Press 1 for WAV (Best for local WiFi, near-instant audio but high bandwidth).
    Press 2 for OPUS (Best for slower networks).
    Press 3 for MP3 (Best if your player checks compatibility).
  Note: If you don't choose within 3 seconds, it defaults to your last choice.
- Connect your Phone:
  On your mobile device, open Bluetooth settings.
  Look for a device name (usually your Linux hostname, e.g., raspberrypi).
  Tap to pair. The script will auto-accept the connection.
- Listen to the Stream:
  The script will print a URL in Cyan, e.g., http://192.168.1.50:8090/stream.wav.
  Open VLC, a web browser, or any audio player on another computer.
  Open "Network Stream" and paste that URL.

Dashboard: The terminal will now show the "Now Playing" information (Artist - Track) updating in real-time as you play music on your phone.
