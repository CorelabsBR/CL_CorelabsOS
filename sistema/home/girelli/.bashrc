# Configuração interativa do Bash.

case "$-" in
    *i*) ;;
    *) return ;;
esac

export HISTSIZE=1000
export HISTFILESIZE=2000
export HISTCONTROL=ignoreboth

PS1='\u@\h:\w\$ '

alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias cls='clear'

# Nem todo caminho precisa ser percorrido com pressa.
