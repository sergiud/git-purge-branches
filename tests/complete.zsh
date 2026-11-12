#!/bin/zsh -f

# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Completes the given command line in an interactive zsh with the completion
# functions of the given directory in front of fpath and prints the matches,
# one per line. Usage: complete.zsh <directory> <command line>
#
# Completion needs the line editor, so the shell runs on a pseudo terminal.
# Wrapping compadd records the matches in a file, since the terminal output of
# the completion list depends on the terminal and the configuration.

emulate -L zsh
setopt err_return

zmodload zsh/zpty

readonly completion_dir=$1
readonly line=$2
readonly matches=$(mktemp)
readonly done_marker='<completion done>'

zpty shell zsh -f -i
# The shell on the pseudo terminal is a fork that would inherit the trap.
trap 'rm -f -- ${matches}' EXIT

zpty -w shell "PROMPT= RPROMPT= PS2="
zpty -w shell "fpath=(${(q)completion_dir} \$fpath)"
zpty -w shell "autoload -Uz compinit && compinit -u -D"
zpty -w shell "bindkey '^I' complete-word"
# Matches added with -O, -A or -D only fill an array and are no candidates.
zpty -w shell "compadd() {
    if [[ \${@[1,(i)(-|--)]} == *-(O|A|D)\\ * ]]; then
        builtin compadd \"\$@\"
        return
    fi
    local -a added
    builtin compadd -A added \"\$@\"
    (( \$#added == 0 )) || print -rl -- \$added >> ${(q)matches}
    builtin compadd \"\$@\"
}"
zpty -w shell "finish() { print -r -- ${(q)done_marker} }"
zpty -w shell "comppostfuncs=(finish)"
zpty -w shell "print -r -- '<ready>'"
zpty -r shell output '*<ready>*'

zpty -w -n shell "${line}"$'\t'
zpty -r shell output "*${done_marker}*"
zpty -d shell

LC_ALL=C sort -u -- ${matches}
