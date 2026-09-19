#!/usr/bin/env bash

# ==============================================================================
# Mac Flap/Lid No-Sleep & Low Brightness Controller
# Keeps your MacBook awake when the lid/flap is closed (for downloads/torrents)
# and lowers the screen brightness to avoid glare & save battery.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$HOME/.cache/nosleepapp"
mkdir -p "$CACHE_DIR" 2>/dev/null || CACHE_DIR="/tmp/nosleepapp-$USER"
mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR" 2>/dev/null || true

BRIGHTNESS_BIN="$CACHE_DIR/brightness_control"
STATE_FILE="$CACHE_DIR/.original_brightness"

# Ensure brightness binary exists
if [[ ! -f "$BRIGHTNESS_BIN" ]]; then
    if [[ -f "$SCRIPT_DIR/brightness.c" ]]; then
        clang -O2 -framework CoreGraphics "$SCRIPT_DIR/brightness.c" -o "$BRIGHTNESS_BIN" 2>/dev/null
        chmod +x "$BRIGHTNESS_BIN"
    fi
fi

get_current_brightness() {
    if [[ -x "$BRIGHTNESS_BIN" ]]; then
        "$BRIGHTNESS_BIN"
    else
        echo "0.50"
    fi
}

set_brightness() {
    local val="$1"
    if [[ -x "$BRIGHTNESS_BIN" ]]; then
        "$BRIGHTNESS_BIN" "$val" >/dev/null 2>&1
    fi
}

get_sleep_status() {
    local ds
    ds=$(pmset -g | grep -i "SleepDisabled" | awk '{print $2}')
    if [[ "$ds" == "1" ]]; then
        echo "ACTIVE (Laptop will STAY AWAKE when flap is closed)"
    else
        echo "INACTIVE (Laptop will sleep normally when flap is closed)"
    fi
}

restore_normal() {
    echo ""
    echo "---------------------------------------------------------"
    echo "Restoring normal settings..."
    
    # Restore prior sleep setting (or 0) using non-blocking sudo where possible
    local prior_val="0"
    if [[ -f "$CACHE_DIR/.prior_sleep" ]]; then
        local raw_prior
        raw_prior=$(cat "$CACHE_DIR/.prior_sleep" 2>/dev/null | tr -d '[:space:]')
        if [[ "$raw_prior" =~ ^[01]$ ]]; then
            prior_val="$raw_prior"
        fi
        rm -f "$CACHE_DIR/.prior_sleep"
    fi
    sudo -n /usr/bin/pmset -a disablesleep "$prior_val" 2>/dev/null || sudo /usr/bin/pmset -a disablesleep "$prior_val" 2>/dev/null
    
    # Restore original brightness if saved
    if [[ -f "$STATE_FILE" ]]; then
        local saved_brightness
        saved_brightness=$(cat "$STATE_FILE")
        if [[ -n "$saved_brightness" ]]; then
            echo "Restoring brightness to: $saved_brightness"
            set_brightness "$saved_brightness"
        fi
        rm -f "$STATE_FILE"
    else
        # Default fallback to 0.40
        set_brightness 0.40
    fi
    
    echo "✓ Normal sleep restored (laptop will sleep when flap is closed)."
    echo "✓ Brightness restored."
    echo "---------------------------------------------------------"
}

parse_duration_seconds() {
    local input="$1"
    if [[ -z "$input" ]]; then
        echo "18000" # Default 5 hours (5 * 3600)
        return
    fi
    if [[ "$input" =~ ^([0-9]+)h$ ]]; then
        echo $((${BASH_REMATCH[1]} * 3600))
    elif [[ "$input" =~ ^([0-9]+)m$ ]]; then
        echo $((${BASH_REMATCH[1]} * 60))
    elif [[ "$input" =~ ^([0-9]+)s$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "$input"
    else
        echo "18000"
    fi
}

format_time() {
    local total="$1"
    local h=$((total / 3600))
    local m=$(((total % 3600) / 60))
    local s=$((total % 60))
    printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

get_battery_percent() {
    pmset -g batt | grep -o "[0-9]\{1,3\}%" | tr -d '%' | head -n 1
}

is_on_ac_power() {
    pmset -g batt | grep -q "AC Power"
}

start_nosleep_mode() {
    local raw_timer="${1:-5h}"
    local target_brightness="${2:-0.05}"
    local duration_secs
    duration_secs=$(parse_duration_seconds "$raw_timer")
    
    echo "========================================================="
    echo "       MAC FLAP NO-SLEEP & LOW BRIGHTNESS MODE           "
    echo "========================================================="
    echo ""
    echo "🛡️  Auto-Off Safety Timer: $(format_time "$duration_secs") ($raw_timer)"
    echo "    (Your Mac will automatically restore sleep when time runs out)"
    
    # Save current brightness
    local curr_brightness
    curr_brightness=$(get_current_brightness)
    echo "$curr_brightness" > "$STATE_FILE"
    echo "• Current display brightness: $curr_brightness (Saved)"
    
    # Request sudo access for pmset
    echo "• Requesting administrator permission to disable lid sleep..."
    if ! sudo -v; then
        echo "❌ Administrator authorization required. Aborting."
        exit 1
    fi
    
    # Set trap to cleanly restore when user stops script or timer expires
    trap restore_normal EXIT INT TERM
    
    # Set low brightness
    echo "• Lowering display brightness to $target_brightness..."
    set_brightness "$target_brightness"
    
    # Record prior sleep setting
    local prior_sleep
    prior_sleep=$(pmset -g | grep -i "SleepDisabled" | awk '{print $2}')
    echo "${prior_sleep:-0}" > "$CACHE_DIR/.prior_sleep"

    # Disable sleep on lid close
    sudo pmset -a disablesleep 1
    
    echo ""
    echo "========================================================="
    echo "   STATUS: ACTIVE                                        "
    echo "   - You can now SHUT THE FLAP (CLOSE THE LID).          "
    echo "   - Your laptop will NOT sleep or switch off!           "
    echo "   - Torrents and background downloads will keep running."
    echo "   - Display brightness is set to LOW (cool display).    "
    echo "   - AUTO-OFF PROTECTION: Will shut off in $(format_time "$duration_secs").  "
    echo "========================================================="
    echo ""
    echo "Press [q] or [Ctrl+C] at any time to exit & restore normal sleep."
    echo ""
    
    local remaining="$duration_secs"
    local check_counter=0
    
    while (( remaining > 0 )); do
        local time_str
        time_str=$(format_time "$remaining")
        printf "\r⏳ Remaining: \033[1;36m%s\033[0m | [q] to quit & restore sleep " "$time_str"
        
        # Check battery health every 2 seconds (near-instant cutoff)
        ((check_counter++))
        if (( check_counter >= 2 )); then
            check_counter=0
            if ! is_on_ac_power; then
                local batt
                batt=$(get_battery_percent)
                if [[ -n "$batt" && "$batt" -le 20 ]]; then
                    echo ""
                    echo ""
                    echo "⚠️  BATTERY SAFEGUARD: Battery is at ${batt}% and unplugged."
                    echo "Restoring normal sleep immediately to protect your battery."
                    break
                fi
            fi
        fi
        
        read -t 1 -n 1 input 2>/dev/null
        if [[ "$input" == "q" || "$input" == "Q" ]]; then
            echo ""
            echo "Stopping by user request..."
            break
        fi
        
        ((remaining--))
    done
    
    if (( remaining <= 0 )); then
        echo ""
        echo ""
        echo "⏰ AUTO-OFF TIMER EXPIRED ($(format_time "$duration_secs"))."
        echo "Restoring normal sleep to prevent laptop overheating."
    fi
}

case "$1" in
    on)
        # Persistent ON: optionally accepts timer and brightness
        # Usage: ./nosleep.sh on [duration e.g. 5h] [brightness e.g. 0.05]
        timer_arg="${2:-5h}"
        target="${3:-0.05}"
        start_nosleep_mode "$timer_arg" "$target"
        ;;
    off)
        restore_normal
        ;;
    status)
        echo "Sleep Status: $(get_sleep_status)"
        echo "Current Brightness: $(get_current_brightness)"
        if [[ -f "$STATE_FILE" ]]; then
            echo "Original Brightness Saved: $(cat "$STATE_FILE")"
        fi
        echo "Battery: $(get_battery_percent)%"
        ;;
    brightness)
        if [[ -n "$2" ]]; then
            set_brightness "$2"
            echo "Brightness set to $2"
        else
            echo "Current brightness: $(get_current_brightness)"
        fi
        ;;
    help|--help|-h)
        echo "Usage:"
        echo "  ./nosleep.sh [5h|2h|30m]   Interactive mode with auto-off timer (default: 5h)"
        echo "  ./nosleep.sh on [5h]      Enable no-sleep with safety timer"
        echo "  ./nosleep.sh off          Immediately restore normal sleep & brightness"
        echo "  ./nosleep.sh status       Check current sleep status, brightness & battery"
        echo "  ./nosleep.sh brightness X Set brightness directly (0.0 to 1.0)"
        ;;
    *)
        start_nosleep_mode "$1"
        ;;
esac
