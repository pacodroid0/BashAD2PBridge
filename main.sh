#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
SERVER_PORT="8090"
VIRTUAL_SINK_NAME="A2DP_Bridge"
CONFIG_FILE="$(dirname "$0")/bt_server.conf"

# ==============================================================================
# UTILS & COLORS
# ==============================================================================
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

function log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
function log_step() { echo -e "${CYAN}[STEP]${NC} ${BOLD}$1${NC}"; }

# ==============================================================================
# ENVIRONMENT FIX
# ==============================================================================
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

# ==============================================================================
# CLEANUP & PORT CHECK
# ==============================================================================
function cleanup_port() {
    printf "\033[?25h" # Show cursor
    if lsof -i :$SERVER_PORT >/dev/null 2>&1; then
        fuser -k -n tcp "$SERVER_PORT" >/dev/null 2>&1
        kill -9 $(lsof -t -i:$SERVER_PORT) >/dev/null 2>&1
    fi
    pkill -f "bt_daemon.exp" 2>/dev/null
    pkill -f "mpris-proxy" 2>/dev/null
    rm -f /tmp/bt_current_mac 2>/dev/null
}

# ==============================================================================
# AUDIO SETUP
# ==============================================================================
function setup_audio_system() {
    log_step "Configuring Audio System..."

    if ! pactl info > /dev/null 2>&1; then
        pulseaudio --start --log-target=syslog
        sleep 2
    fi
    pactl unload-module module-suspend-on-idle > /dev/null 2>&1

    if ! pactl list modules | grep -q "module-bluez5-discover"; then
        pactl load-module module-bluez5-discover > /dev/null 2>&1
    fi
    if ! pactl list modules | grep -q "module-bluetooth-policy"; then
        pactl load-module module-bluetooth-policy auto_switch=2 > /dev/null 2>&1
    fi

    if ! pactl list short sinks | grep -q "$VIRTUAL_SINK_NAME"; then
        pactl load-module module-null-sink sink_name="$VIRTUAL_SINK_NAME" rate=44100 sink_properties=device.description="A2DP_Monitor" > /dev/null
    fi
    pactl set-sink-mute "$VIRTUAL_SINK_NAME" 0 > /dev/null 2>&1
    pactl set-sink-volume "$VIRTUAL_SINK_NAME" 100% > /dev/null 2>&1

    #pactl list short sources | grep -v "bluez" | grep -v ".monitor" | awk '{print $2}' | while read -r src; do
    #    pactl set-source-mute "$src" 1 > /dev/null 2>&1
    #done
}

# ==============================================================================
# BT CHECK
# ==============================================================================

function init_bluetooth() {
    log_info "Initializing Bluetooth..."
    /usr/sbin/rfkill unblock all
    sleep 1
    if ! bluetoothctl show | grep -q "Powered: yes"; then
        echo "power on" | bluetoothctl > /dev/null 2>&1
        sleep 1
    fi
    mpris-proxy >/dev/null 2>&1 &
}

# ==============================================================================
# CODEC SELECTION
# ==============================================================================

function select_codec() {
    if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; DEFAULT_VAL="$LAST_CHOICE"; else DEFAULT_VAL="1"; fi
    clear
    echo "========================================================"
    echo " FORMAT SELECTION"
    echo "========================================================"
    echo "1) PCM WAV - Best latency"
    echo "2) OPUS 128k - Minimum bandwith"
    echo "3) MP3 192k - Maximum Compatibility"
    echo "========================================================"
    echo -e "${YELLOW}Waiting 3s... (Default: $DEFAULT_VAL)${NC}"
    if read -t 3 -p "Choice (1/3): " USER_CHOICE; then echo ""; else echo ""; USER_CHOICE="$DEFAULT_VAL"; fi
    if [[ ! "$USER_CHOICE" =~ ^[1-3]$ ]]; then USER_CHOICE="$DEFAULT_VAL"; fi
    echo "LAST_CHOICE=$USER_CHOICE" > "$CONFIG_FILE"

    COMMON_FLAGS="-fflags +nobuffer -flags +low_delay -probesize 4096 -analyzeduration 0"

    case "$USER_CHOICE" in
        2)
            FFMPEG_FLAGS="$COMMON_FLAGS -c:a libopus -b:a 128k -application lowdelay -frame_duration 5 -content_type application/ogg -f ogg"
            STREAM_EXT="ogg" ;;
        3)
            FFMPEG_FLAGS="$COMMON_FLAGS -c:a libmp3lame -b:a 192k -reservoir 0 -content_type audio/mpeg -f mp3"
            STREAM_EXT="mp3" ;;
        *)
            FFMPEG_FLAGS="$COMMON_FLAGS -c:a pcm_s16le -content_type audio/wav -f wav"
            STREAM_EXT="wav" ;;
    esac
}

# ==============================================================================
# BACKGROUND AGENT
# ==============================================================================
function start_persistent_agent() {
    log_info "Starting Background Pairing Agent..."
    cat <<EOF > /tmp/bt_daemon.exp
#!/usr/bin/expect -f
set timeout -1
spawn bluetoothctl
send "agent off\r"
sleep 1
send "agent KeyboardDisplay\r"
sleep 1
send "default-agent\r"
sleep 1
send "power on\r"
send "discoverable on\r"
send "pairable on\r"
expect {
    -re ".*(yes/no).*" { send "yes\r"; exp_continue }
    "Confirm passkey" { send "yes\r"; exp_continue }
    "Authorize service" { send "yes\r"; exp_continue }
    -re "Device (\[0-9A-Fa-f:]+) Connected: yes" {
        set dev_mac \$expect_out(1,string)
        send "trust \$dev_mac\r"
        exp_continue
    }
    "Connection" { exp_continue }
    "Device" { exp_continue }
    eof { exit 1 }
}
EOF
    chmod +x /tmp/bt_daemon.exp
    /tmp/bt_daemon.exp > /dev/null 2>&1 &
}

# ==============================================================================
# START FFMPEG
# ==============================================================================
function start_ffmpeg_server() {
    HOST_IP=$(hostname -I | awk '{print $1}')
    FULL_URL="http://${HOST_IP}:${SERVER_PORT}/stream.${STREAM_EXT}"

    echo "========================================================"
    echo -e " DIRECT STREAM URL: ${BOLD}${CYAN}${FULL_URL}${NC}"
    echo "========================================================"
    log_info "Starting Audio Server..."

    while true; do
        while lsof -i :$SERVER_PORT >/dev/null 2>&1; do sleep 1; done
        ffmpeg -hide_banner -loglevel fatal \
               -f pulse -i "${VIRTUAL_SINK_NAME}.monitor" \
               -ac 2 \
               $FFMPEG_FLAGS \
               -listen 1 \
               "http://0.0.0.0:${SERVER_PORT}"
        sleep 1
    done &
}

# ==============================================================================
# DYNAMIC BRIDGE
# ==============================================================================
function manage_bluetooth_bridge() {
    local CURRENT_LOOPBACK_ID=""
    local LAST_BT_SOURCE=""
    local MISSING_COUNT=0

    while true; do
        BT_SRC=$(pactl list short sources | grep "bluez_source" | awk '{print $2}' | head -n 1)

        if [ -n "$BT_SRC" ]; then
            MISSING_COUNT=0
            if [ "$BT_SRC" != "$LAST_BT_SOURCE" ]; then
                pactl suspend-source "$BT_SRC" 0 2>/dev/null
                pactl set-source-mute "$BT_SRC" 0 2>/dev/null
                pactl set-source-volume "$BT_SRC" 100% 2>/dev/null

                DEFAULT_SINK=$(pactl get-default-sink 2>/dev/null)
                if [ -n "$DEFAULT_SINK" ] && [ "$DEFAULT_SINK" != "$VIRTUAL_SINK_NAME" ]; then
                     :
                fi

                if [ -z "$CURRENT_LOOPBACK_ID" ]; then
                    OUTPUT=$(pactl load-module module-loopback source="$BT_SRC" sink="$VIRTUAL_SINK_NAME" latency_msec=100 2>&1)
                    if [ $? -eq 0 ] && [[ "$OUTPUT" =~ ^[0-9]+$ ]]; then
                        CURRENT_LOOPBACK_ID="$OUTPUT"
                    fi
                fi
                LAST_BT_SOURCE="$BT_SRC"
                DEVICE_MAC=$(echo "$BT_SRC" | grep -oE "([0-9A-F]{2}_){5}[0-9A-F]{2}" | tr '_' ':')
                echo "trust $DEVICE_MAC" | bluetoothctl > /dev/null 2>&1

                echo "$DEVICE_MAC" > /tmp/bt_current_mac
            fi

            if [ -n "$CURRENT_LOOPBACK_ID" ]; then
                if ! pactl list short modules | grep -q "^$CURRENT_LOOPBACK_ID"; then
                     CURRENT_LOOPBACK_ID=""
                     LAST_BT_SOURCE=""
                fi
            fi
        else
            ((MISSING_COUNT++))
            if [ $MISSING_COUNT -gt 2 ]; then
                if [ -n "$CURRENT_LOOPBACK_ID" ]; then
                    pactl unload-module "$CURRENT_LOOPBACK_ID" > /dev/null 2>&1
                    CURRENT_LOOPBACK_ID=""
                    LAST_BT_SOURCE=""
                    rm -f /tmp/bt_current_mac
                fi
            fi
        fi
        sleep 1
    done
}

# ==============================================================================
# DASHBOARD
# ==============================================================================
function get_metadata_direct() {
    local MAC="$1"
    local DEV_PATH="/org/bluez/hci0/dev_$(echo $MAC | tr ':' '_')/player0"

    local TRACK_INFO=$(dbus-send --system --print-reply --dest=org.bluez "$DEV_PATH" org.freedesktop.DBus.Properties.Get string:org.bluez.MediaPlayer1 string:Track 2>/dev/null)
    local STATUS_RAW=$(dbus-send --system --print-reply --dest=org.bluez "$DEV_PATH" org.freedesktop.DBus.Properties.Get string:org.bluez.MediaPlayer1 string:Status 2>/dev/null)

    if [[ "$STATUS_RAW" == *"playing"* ]]; then echo "STATUS:PLAYING"; else echo "STATUS:PAUSED"; fi

    local TITLE=$(echo "$TRACK_INFO" | grep -A 1 "Title" | tail -n 1 | cut -d '"' -f 2)
    local ARTIST=$(echo "$TRACK_INFO" | grep -A 1 "Artist" | tail -n 1 | cut -d '"' -f 2)

    echo "TITLE:$TITLE"
    echo "ARTIST:$ARTIST"
}

function start_dashboard() {
    printf "\033[?25l" # Hide cursor
    sleep 3
    echo "" # Reserve 1 line space

    local LAST_OUTPUT_STR=""
    local HAS_PRINTED=0

    while true; do
        if [ -f /tmp/bt_current_mac ]; then
            CURRENT_MAC=$(cat /tmp/bt_current_mac)

            # Double check connectivity
            if ! bluetoothctl info "$CURRENT_MAC" | grep -q "Connected: yes"; then
                rm -f /tmp/bt_current_mac
                continue
            fi

            RAW_DATA=$(get_metadata_direct "$CURRENT_MAC")

            STATUS=$(echo "$RAW_DATA" | grep "STATUS:" | cut -d: -f2)
            TITLE=$(echo "$RAW_DATA" | grep "TITLE:" | cut -d: -f2)
            ARTIST=$(echo "$RAW_DATA" | grep "ARTIST:" | cut -d: -f2)

            if [ -z "$TITLE" ]; then TITLE="Unknown Track"; fi
            if [ -z "$ARTIST" ]; then ARTIST="Bluetooth Audio"; fi

            # TRUNCATE to avoid wrapping issues
            D_TITLE="${TITLE:0:45}"
            D_ARTIST="${ARTIST:0:30}"

            if [ "$STATUS" == "PLAYING" ]; then
                S_ICON="${GREEN}▶ PLAYING${NC}"
            else
                S_ICON="${YELLOW}⏸ PAUSED ${NC}"
            fi

            # SINGLE LINE OUTPUT
            CURRENT_OUTPUT_STR="${S_ICON} ${BOLD}${CYAN}${D_ARTIST} - ${D_TITLE}${NC}"

            if [ "$CURRENT_OUTPUT_STR" != "$LAST_OUTPUT_STR" ]; then
                if [ $HAS_PRINTED -eq 1 ]; then
                    printf "\033[1A" # Go up 1 line
                fi
                printf "\r\033[K%b\n" "$CURRENT_OUTPUT_STR"
                LAST_OUTPUT_STR="$CURRENT_OUTPUT_STR"
                HAS_PRINTED=1
            fi

        else
            # Waiting Screen
            WAIT_STR="${YELLOW}[WAITING]${NC} Connect phone via Bluetooth..."
            if [ "$WAIT_STR" != "$LAST_OUTPUT_STR" ]; then
                if [ $HAS_PRINTED -eq 1 ]; then
                    printf "\033[1A"
                fi
                printf "\r\033[K%b\n" "$WAIT_STR"
                LAST_OUTPUT_STR="$WAIT_STR"
                HAS_PRINTED=1
            fi
        fi
        sleep 1
    done
}

# ==============================================================================
# MAIN
# ==============================================================================
trap "cleanup_port; exit" SIGINT SIGTERM

cleanup_port
init_bluetooth
setup_audio_system
select_codec
start_persistent_agent
start_ffmpeg_server
manage_bluetooth_bridge &
start_dashboard
