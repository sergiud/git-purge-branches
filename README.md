<!--
SPDX-FileCopyrightText: 2026 Sergiu Deitsch

SPDX-License-Identifier: GPL-3.0-or-later
-->

# git-purge-branches

`git purge-branches` deletes the local branches merged into a commit, `HEAD`
by default, and keeps the branches checked out in any worktree.

```bash
git purge-branches --dry-run
git purge-branches
```

The [manual](https://sergiud.github.io/git-purge-branches/) describes the
options, the branches the command keeps and how it differs from
`git branch --delete-merged`.

## Installation

```bash
curl -fsSL https://sergiud.github.io/git-purge-branches/install.sh | bash
```

installs the latest release below `~/.local`, or below `/usr/local` as root.
Arguments after `bash -s --` select another prefix with `--prefix=<dir>` or
another release with `--version=<version>`, and `--uninstall` removes the
release again. Git, `man` and the shells find the files below `~/.local` once
`~/.local/bin` is in `PATH`, except zsh, which needs the directory of its
completions in `fpath`, set in `~/.zshrc` before `compinit` runs:

```zsh
fpath=(~/.local/share/zsh/site-functions $fpath)
```

Each release also provides a Debian and a pacman package.

## Development

The recipes need [just](https://just.systems) 1.46 or later. `just test` runs
the tests, `just install` installs the checkout, and `just deb`, `just pacman`
and `just tarball` build the packages into `dist/`. `just --list` shows every
recipe.

## License

GPL-3.0-or-later, see [`LICENSES`](LICENSES/GPL-3.0-or-later.txt).
