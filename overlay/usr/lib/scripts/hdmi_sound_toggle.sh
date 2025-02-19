#!/bin/bash

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Ensure script is run with correct locale
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required commands
for cmd in pactl id whoami udevadm; do
    if ! command_exists "$cmd"; then
        log "Error: Required command '$cmd' not found"
        exit 1
    fi
done

# Get user information
USER_NAME=$(whoami)
USER_ID=$(id -u "$USER_NAME" 2>/dev/null || {
    log "Error: Failed to get user ID"
    exit 1
})

# Define paths and variables
CARD_PATH="/sys/class/drm/card0"
PULSE_SERVER="unix:/run/user/$USER_ID/pulse/native"
DEFAULT_OUTPUT="alsa_output.platform-es8388-sound.stereo-fallback"

# Function to get HDMI sinks
get_hdmi_sinks() {
    pactl list short sinks 2>/dev/null | grep -i 'hdmi' | awk '{print $2}' | sort -t'-' -k3,3n
}

# Function to switch audio output
switch_audio() {
    local output="$1"
    log "Switching audio output to: $output"
    if ! sudo -u "$USER_NAME" PULSE_SERVER="$PULSE_SERVER" pactl set-default-sink "$output" 2>/dev/null; then
        log "Error: Failed to set default sink to $output"
        return 1
    fi
    return 0
}

# Function to handle HDMI connection
handle_hdmi_connection() {
    # Create output mapping
    declare -A OUTPUT_MAP
    index=1
    while read -r hdmi; do
        [[ -n "$hdmi" ]] && OUTPUT_MAP["card0-HDMI-A-$index"]="$hdmi"
        ((index++))
    done < <(get_hdmi_sinks)

    # Initialize audio output to default
    AUDIO_OUTPUT="$DEFAULT_OUTPUT"

    # Check connected outputs
    while read -r OUTPUT; do
        if [[ -f "$CARD_PATH/$OUTPUT/status" ]]; then
            OUT_STATUS=$(cat "$CARD_PATH/$OUTPUT/status" 2>/dev/null || echo "disconnected")
            if [[ "$OUT_STATUS" == "connected" ]]; then
                log "Found connected output: $OUTPUT"
                if [[ -n "${OUTPUT_MAP[$OUTPUT]:-}" ]]; then
                    AUDIO_OUTPUT="${OUTPUT_MAP[$OUTPUT]}"
                    log "Mapped to audio output: $AUDIO_OUTPUT"
                    switch_audio "$AUDIO_OUTPUT"
                    return
                fi
            fi
        fi
    done < <(cd "$CARD_PATH" 2>/dev/null && echo card*)

    # If no HDMI connected, switch to default output
    switch_audio "$DEFAULT_OUTPUT"
}

# Function to monitor HDMI events
monitor_hdmi() {
    log "Starting HDMI monitor..."
    udevadm monitor --kernel --subsystem-match=drm | while read -r line; do
        if [[ $line == *"KERNEL"*"change"*"card0"* ]]; then
            log "Detected HDMI change event"
            sleep 1  # Give system time to stabilize
            handle_hdmi_connection
        fi
    done
}

# Initial setup
handle_hdmi_connection

# Start monitoring
monitor_hdmi