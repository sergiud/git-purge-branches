# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Fish completion of git-purge-branches. The completion of git forwards git
# purge-branches to it if git-purge-branches is in PATH.

# The completion of git defines __fish_git_refs, so load it for
# git-purge-branches on its own.
if not functions --query __fish_git_refs
    complete --do-complete 'git ' >/dev/null
end

complete --command git-purge-branches --no-files

complete --command git-purge-branches \
    --condition 'not __fish_seen_argument --short h --long help' \
    --condition 'not __fish_seen_argument --short n --long dry-run' \
    --short-option n --long-option dry-run \
    --description 'List the branches that would be deleted instead'
complete --command git-purge-branches \
    --condition 'not __fish_seen_argument --short h --long help' \
    --condition 'not __fish_seen_argument --short e --long equivalent' \
    --short-option e --long-option equivalent \
    --description 'Also delete branches whose commits all have an equivalent in the commit'
complete --command git-purge-branches \
    --condition 'not __fish_seen_argument --short h --long help' \
    --short-option h --long-option help \
    --description 'Show the help'

# After --, __fish_git_refs takes -- for a global option of git and lists no
# refs.
complete --command git-purge-branches \
    --condition 'not __fish_seen_argument --short h --long help' \
    --condition '__fish_is_nth_token 1' \
    --arguments '(__fish_git_refs)'
