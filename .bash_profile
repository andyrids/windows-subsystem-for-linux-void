# .bash_profile

# load .profile settings
[ -f $HOME/.profile ] && source $HOME/.profile

# https://github.com/fastfetch-cli/fastfetch
# sudo xbps-install fastfetch
fastfetch

# start `keychain` & add specified keys.
# 1. id_ed25519_github - GitHub SSH key
# 2. id_ed25519_gitlab - GitLab SSH key
if command -v keychain &> /dev/null; then
    echo "Initializing keychain and ssh-agent..."
    # 240 minute timeout & only print warning or error messages
    eval $(keychain --eval --timeout 240 --quiet id_ed25519_github id_ed25519_gitlab)
else
    echo "keychain command not found. SSH agent may not be configured correctly."
fi

# Get the aliases and functions
[ -f $HOME/.bashrc ] && source $HOME/.bashrc

# source any custom environment variables if this file exists
[ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"
