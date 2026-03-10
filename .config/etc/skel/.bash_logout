# ~/.bash_logout executed by bash(1) when login shell exits
reset
echo ".bash_logout"
echo "executing: history -c && history -w" && history -c && history -w 2>/dev/null || true