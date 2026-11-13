# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Bash completion of git purge-branches and git-purge-branches. Installed as
# git-purge-branches.bash in a completions directory of bash-completion, such
# as ~/.local/share/bash-completion/completions, it is loaded on demand by the
# completion of git for git purge-branches and by bash-completion for
# git-purge-branches.

# Completes an option, or a commit for a word that is no option or follows --.
# The completion of git calls this function by its name for git
# purge-branches and sets cur to the word to complete.
_git_purge_branches()
{
    # shellcheck disable=SC2154 # the completion of git sets cur
    if [[ ${cur} == -* ]] && ! __git_has_doubledash; then
        __gitcomp "--dry-run --equivalent --exclude= --help --include= --interactive --older-than= --version"
        return
    fi

    __git_complete_refs
}

# The command git-purge-branches needs the functions of the completion of git,
# which bash-completion loads on demand as well. The completion of git is
# already loaded when it loads this file for git purge-branches.
if ! declare -F __git_complete >/dev/null; then
    _completion_loader git
fi

__git_complete git-purge-branches _git_purge_branches
