# ~/.bash_logout executed by bash(1) when login shell exits

if [ -t 0 ]; then
    # Only reset if on an interactive terminal
    clear
fi

history -c && history -w 2>/dev/null || true

# Gracefully stop `just-lsp`
if pidof just-lsp > /dev/null 2>&1; then
    echo "Stopping just-lsp..."
    pkill -15 just-lsp
fi

# Gracefully stop `Podman` & running containers
if command -v podman >/dev/null 2>&1; then
    RUNNING_CONTAINERS=$(podman ps -q 2>/dev/null)
    if [ -n "$RUNNING_CONTAINERS" ]; then
        echo "Stopping Podman containers..."
        podman stop $RUNNING_CONTAINERS >/dev/null 2>&1
    fi

    if pidof podman >/dev/null 2>&1; then
        pkill -15 podman
    fi
fi
