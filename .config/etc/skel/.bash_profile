# .bash_profile

# load .profile settings
[ -f "$HOME/.profile" ] && source "$HOME/.profile"

# Get the aliases and functions
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"

# https://github.com/fastfetch-cli/fastfetch
command -v fastfetch >/dev/null 2>&1 && fastfetch