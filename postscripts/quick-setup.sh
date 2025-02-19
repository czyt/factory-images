#!/bin/bash

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Configuration
CARD_PATH="/sys/class/drm/card0"
DEFAULT_OUTPUT="alsa_output.platform-es8388-sound.stereo-fallback"

# Get the first active user session
get_active_user() {
    who | grep -w '(:0)' | head -n1 | awk '{print $1}'
}

# Get user ID from username
get_user_id() {
    id -u "$1"
}

# Function to get HDMI sinks
get_hdmi_sinks() {
    local user="$1"
    sudo -u "$user" PULSE_SERVER="unix:/run/user/$2/pulse/native" \
        pactl list short sinks | grep -i 'hdmi' | awk '{print $2}' | sort -t'-' -k3,3n
}

# Function to switch audio output
switch_audio() {
    local user="$1"
    local user_id="$2"
    local output="$3"
    
    sudo -u "$user" PULSE_SERVER="unix:/run/user/$user_id/pulse/native" \
        pactl set-default-sink "$output"
}

# Main execution
main() {
    # Get active user information
    USER_NAME=$(get_active_user)
    [ -z "$USER_NAME" ] && exit 1
    
    USER_ID=$(get_user_id "$USER_NAME")
    [ -z "$USER_ID" ] && exit 1

    # Create output mapping
    declare -A OUTPUT_MAP
    index=1
    while read -r hdmi; do
        [[ -n "$hdmi" ]] && OUTPUT_MAP["card0-HDMI-A-$index"]="$hdmi"
        ((index++))
    done < <(get_hdmi_sinks "$USER_NAME" "$USER_ID")

    # Initialize audio output to default
    AUDIO_OUTPUT="$DEFAULT_OUTPUT"

    # Check connected outputs
    while read -r OUTPUT; do
        if [[ -f "$CARD_PATH/$OUTPUT/status" ]]; then
            OUT_STATUS=$(cat "$CARD_PATH/$OUTPUT/status")
            if [[ "$OUT_STATUS" == "connected" ]]; then
                if [[ -n "${OUTPUT_MAP[$OUTPUT]:-}" ]]; then
                    AUDIO_OUTPUT="${OUTPUT_MAP[$OUTPUT]}"
                    break
                fi
            fi
        fi
    done < <(cd "$CARD_PATH" && echo card*)

    # Switch audio output
    switch_audio "$USER_NAME" "$USER_ID" "$AUDIO_OUTPUT"
}

# Add small delay to ensure system is ready
sleep 1

# Execute main function
main