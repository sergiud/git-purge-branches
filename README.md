<!--
SPDX-FileCopyrightText: 2026 Sergiu Deitsch

SPDX-License-Identifier: GPL-3.0-or-later
-->

# git-purge-branches

`git purge-branches` deletes the local branches merged into a commit, `HEAD`
by default. It keeps the branches checked out in any worktree and those exempt
through `branch.<name>.deleteMerged`. The option `--equivalent` additionally
deletes branches that a remote such as GitLab or GitHub rebased before merging,
which the default keeps since their commits differ from the merged ones.

```bash
git purge-branches --dry-run
git purge-branches
```

`git branch --delete-merged` selects branches by their upstream and keeps those
without one or with a deleted one. `git purge-branches` deletes the branches
merged into the commit whether they track a remote branch or not, so it also
cleans up topic branches whose remote branches were merged and deleted.

## Installation

The recipes need [just](https://just.systems) 1.46 or later.

`just install` copies the script, its manual page and the completions for
Bash, zsh and fish below a prefix, `/usr/local` when run as root and
`~/.local` otherwise. `--prefix` selects another prefix, and `DESTDIR` stages
the files below a directory, as for a package:

```bash
just install
sudo just install --prefix=/usr
DESTDIR=/tmp/stage just install --prefix=/usr
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

## Packages

`just deb`, `just pacman` and `just tarball` build packages of a release into
`dist/`:

| Recipe | Package | Needs |
| --- | --- | --- |
| `just deb` | `git-purge-branches_1.2.3_all.deb` | `dpkg-buildpackage`, debhelper |
| `just pacman` | `git-purge-branches-1.2.3-1-any.pkg.tar.zst` | `makepkg` |
| `just tarball` | `git-purge-branches-1.2.3.tar.gz` | |

The version is that of the sources: the tag of the commit without a leading
`v`, such as 1.2.3, a tag followed by `.r<count>.<hash>` for later commits, or
`0.r<count>.<hash>` without a tag. An archive of a tagged commit, such as the
source code that GitHub offers for a release, carries its version without git.
`--version=1.2.3` sets another one.

The top-level directory of the tarball holds the install layout:

```bash
tar -xzf git-purge-branches-1.2.3.tar.gz --strip-components=1 -C ~/.local
```

On Arch Linux, `makepkg -D pacman` in the sources builds the package as well,
and records the version in `pacman/PKGBUILD`.

Publishing a release on GitHub attaches the three packages to the release, with
the version taken from its tag.

## License

GPL-3.0-or-later, see [`LICENSES`](LICENSES/GPL-3.0-or-later.txt).
