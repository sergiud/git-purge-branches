<!--
SPDX-FileCopyrightText: 2026 Sergiu Deitsch

SPDX-License-Identifier: GPL-3.0-or-later
-->

# git-purge-branches

`git purge-branches` deletes the local branches merged into a commit, `HEAD`
by default. It keeps the branches checked out in any worktree and those exempt
through `branch.<name>.deleteMerged`. With `--equivalent`, it also deletes
branches that a remote such as GitLab or GitHub rebased before merging.

```console
$ git purge-branches --dry-run --equivalent
$ git purge-branches --equivalent
```

The manual page in `doc/man/git-purge-branches.adoc` describes every option,
the exit status and how the command differs from
`git branch --delete-merged`.

## Installation

The command is a single Bash script. Add this directory to `PATH`, and Git
runs the script as `git purge-branches`. To build the manual page, run

```console
$ just man
```

which writes it below `man/`, where `man` finds it while this directory is in
`PATH`. Then `git purge-branches --help` or `man git-purge-branches` shows it.

Run the tests with `just test`.

## License

GPL-3.0-or-later, see [`LICENSES`](LICENSES/GPL-3.0-or-later.txt).
