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

The recipes need [just](https://just.systems) 1.46 or later.

`just install` copies the script, its manual page and the completions for
Bash, zsh and fish below a prefix, `/usr/local` when run as root and
`~/.local` otherwise. `--prefix` selects another prefix, and `DESTDIR` stages
the files below a directory, as for a package:

```console
$ just install
$ sudo just install --prefix=/usr
$ DESTDIR=/tmp/stage just install --prefix=/usr
```

`just install-completions` installs only the completions, and
`just install-bash-completion`, `install-zsh-completion` and
`install-fish-completion` only the one of a shell. Each has an `uninstall`
counterpart, such as `just uninstall-zsh-completion`, which removes the same
files from the same prefix.

Below `~/.local`, Git, `man`, Bash and fish find the files once `~/.local/bin`
is in `PATH`. zsh searches only system directories, so add the user one to
`fpath` in `~/.zshrc` before `compinit` runs:

```zsh
fpath=(~/.local/share/zsh/site-functions $fpath)
```

Run the tests with `just test`.

## License

GPL-3.0-or-later, see [`LICENSES`](LICENSES/GPL-3.0-or-later.txt).
