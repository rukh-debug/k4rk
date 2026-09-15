#  Shell integration for the island terminal.
#
#  Marks where each command starts and where it ends, so the bar can
#  measure it, fold its output, tell when a long one finishes, and
#  know the directory a session walks in. These are the conventions
#  everyone already speaks — OSC 133 from iTerm2, OSC 633 from VS
#  Code, OSC 7 for the directory — so sourcing this does no harm to
#  any other terminal: it stays quiet unless it is ours.
#
#  In ~/.zshrc, either directly:
#
#      source /path/to/k4/plugins/Terminal/integration.zsh
#
#  or through the variable k4term's installer also understands:
#
#      [ -n "$K4TERM_INTEGRACION" ] && source "$K4TERM_INTEGRACION"
#
#  The function names match k4term's own integration on purpose:
#  add-zsh-hook does not register a function twice, so whichever file
#  is sourced first wins and the other becomes a no-op — installing
#  k4term later (or removing it) cannot leave double marks.

[[ "$TERM_PROGRAM" == "k4term" ]] || return 0
(( $+functions[_k4term_precmd] )) && return 0

_k4term_precmd() {
    local salida=$?
    printf '\033]133;D;%s\007' "$salida"
    printf '\033]7;file://%s%s\007' "${HOST:-$(hostname)}" "$PWD"
    printf '\033]133;A\007'
}

_k4term_preexec() {
    printf '\033]633;E;%s\007' "$1"
    printf '\033]133;C\007'
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _k4term_precmd
add-zsh-hook preexec _k4term_preexec
