# ~/.bash_logout executed by bash(1) when login shell exits

if [ -t 0 ]; then
    # Only reset if on an interactive terminal
    clear
fi
echo ".bash_logout"
history -c && history -w 2>/dev/null || true