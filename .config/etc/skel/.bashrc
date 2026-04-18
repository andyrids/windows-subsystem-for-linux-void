# .bashrc

# if not running interactively, don't do anything
[[ $- != *i* ]] && return

# Do not put duplicate lines or lines starting with space in the history
HISTCONTROL=ignoreboth

# Append to the history file
shopt -s histappend

# For setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# Check window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# Enable colour support for the terminal
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# Set colour prompt (\[...\] wrappers for bash)
if [ "$color_prompt" = yes ]; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='[\u@\h \W]\$ '
fi
unset color_prompt

# Set terminal title (if using xterm)
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# Colour aliases for BusyBox applets
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Common aliases for ls
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Common aliases for Just
alias j='just'
alias jg='just -g'
alias justg='just -g'

JUST_COMPLETIONS="$HOME/.local/share/bash-completion/completions"

# Load any Just recipe completions
if [ -f "$JUST_COMPLETIONS/just" ]; then
    source "$JUST_COMPLETIONS/just"

    # Reuse `just` completion for global aliases by injecting `-g`.
    if complete -p just >/dev/null 2>&1; then
        _just_complete_spec="$(complete -p just 2>/dev/null)"

        if [[ "$_just_complete_spec" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
            _just_complete_func="${BASH_REMATCH[1]}"

            _just_global_alias_completion() {
                local -a _orig_words=("${COMP_WORDS[@]}")
                local _orig_cword="$COMP_CWORD"

                COMP_WORDS=(just -g "${_orig_words[@]:1}")
                COMP_CWORD=$((_orig_cword + 1))

                "$_just_complete_func"

                COMP_WORDS=("${_orig_words[@]}")
                COMP_CWORD="$_orig_cword"
            }

            _just_alias_spec="${_just_complete_spec% just}"
            _just_alias_spec="${_just_alias_spec/-F $_just_complete_func/-F _just_global_alias_completion}"

            eval "${_just_alias_spec} jg"
            eval "${_just_alias_spec} justg"

            unset _just_alias_spec
        fi

        unset _just_complete_spec
    fi
fi

# Load environment variables
if [ -f "$HOME/.local/bin/env" ]; then
    . "$HOME/.local/bin/env"
fi
