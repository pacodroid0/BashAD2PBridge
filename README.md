# BashA2DPBridge
This script transforms a Linux device (likely a Raspberry Pi or a headless server) into a Bluetooth Audio Receiver and HTTP Streaming Bridge.

Bluetooth Receiver (A2DP): It initializes the Bluetooth adapter, makes the device discoverable, and uses a background expect script to automatically accept incoming pairing requests and trust devices.

Audio Routing Bridge: It creates a virtual audio sink (A2DP_Bridge). It automatically detects when a phone connects via Bluetooth and creates a "loopback" module in PulseAudio to route the phone's audio into this virtual sink.

HTTP Audio Server: It uses ffmpeg to capture audio from the virtual sink's monitor and streams it over HTTP on port 8090. This allows you to listen to the Bluetooth audio on a different device via a network stream.

Codec Transcoding: It offers a menu to select the streaming format: WAV (low latency), OPUS (low bandwidth), or MP3 (compatibility).

Metadata Dashboard: It queries the D-Bus system to fetch the currently playing track (Artist/Title) and status (Playing/Paused) from the connected Bluetooth device and displays it in the terminal.

This script is designed to automate Bluetooth device pairing and management on Linux systems using bluetoothctl1 and route the audio stream to a network socket.

The script initializes a background pairing agent with the following capabilities:
- Automated Environment Setup: It disables existing agents before initializing a new KeyboardDisplay agent and setting it as the default3.
- Controller Configuration: Automatically ensures the Bluetooth controller is powered on and set to both discoverable and pairable modes4.Interaction Automation: Uses expect to monitor for "yes/no" prompts, "Confirm passkey" requests, and "Authorize service" messages, automatically replying with "yes"5.
- Automatic Trusting: Detects successful connections via regex, extracts the device MAC address, and issues a trust command to ensure the device can reconnect in the future without intervention6.

# Security Note
This script automatically trusts and authorizes Bluetooth devices that attempt to connect14. It is intended for controlled environments where manual pairing interaction is impossible
