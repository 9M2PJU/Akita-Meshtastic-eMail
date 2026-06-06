#!/bin/bash
set -e

MODE=$1

if [ -z "$MODE" ]; then
    MODE="both"
elif [ "$MODE" = "both" ] || [ "$MODE" = "plugin" ] || [ "$MODE" = "companion" ]; then
    shift
elif [[ "$MODE" == -* ]]; then
    # If it starts with a hyphen, default to 'both' and do not shift arguments
    MODE="both"
else
    # It's a custom command (e.g. python, bash, sh)
    MODE="custom"
fi

# Determine connection arguments from environment variables
CONN_ARGS=()
if [ -n "$AKITA_MESHTASTIC_HOST" ]; then
    CONN_ARGS+=( "--host" "$AKITA_MESHTASTIC_HOST" )
elif [ -n "$AKITA_MESHTASTIC_PORT" ]; then
    CONN_ARGS+=( "--port" "$AKITA_MESHTASTIC_PORT" )
fi

# Cleanup handler to stop background processes on container exit
cleanup() {
    echo "Stopping background processes..."
    if [ ! -z "$PLUGIN_PID" ]; then
        kill "$PLUGIN_PID" 2>/dev/null || true
    fi
    if [ ! -z "$SOCAT_PID" ]; then
        kill "$SOCAT_PID" 2>/dev/null || true
    fi
}

if [ "$MODE" = "both" ]; then
    echo "=== Starting Akita eMail in DUAL mode ==="
    trap cleanup SIGINT SIGTERM EXIT

    echo "1. Creating virtual serial loopback using socat..."
    socat -d -d PTY,link=/tmp/vtty-plugin,raw,echo=0 PTY,link=/tmp/vtty-companion,raw,echo=0 &
    SOCAT_PID=$!

    # Wait for the symlinks to be established
    for i in {1..20}; do
        if [ -L /tmp/vtty-plugin ] && [ -L /tmp/vtty-companion ]; then
            break
        fi
        sleep 0.2
    done

    if [ ! -L /tmp/vtty-plugin ] || [ ! -L /tmp/vtty-companion ]; then
        echo "Error: socat failed to initialize virtual serial link."
        exit 1
    fi

    # Override companion serial port environment variables to route over virtual serial
    export AKITA_COMPANION_SERIAL_PORT=/tmp/vtty-plugin
    export AKITA_COMPANION_PLUGIN_PORT=/tmp/vtty-companion

    echo "2. Launching Akita Plugin process..."
    python run_plugin.py "${CONN_ARGS[@]}" "$@" &
    PLUGIN_PID=$!

    # Allow the plugin a moment to connect to Meshtastic and start listening
    sleep 2

    if ! kill -0 "$PLUGIN_PID" 2>/dev/null; then
        echo "Error: Akita Plugin process failed to start."
        exit 1
    fi

    echo "3. Launching interactive Akita Companion CLI..."
    python run_companion.py

elif [ "$MODE" = "plugin" ]; then
    echo "=== Starting Akita Plugin (standalone) ==="
    exec python run_plugin.py "${CONN_ARGS[@]}" "$@"

elif [ "$MODE" = "companion" ]; then
    echo "=== Starting Akita Companion CLI (standalone) ==="
    exec python run_companion.py "$@"

elif [ "$MODE" = "custom" ]; then
    exec "$@"
fi
