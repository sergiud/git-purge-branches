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

Each release also provides a Debian and a pacman package. In a checkout,
`just install` installs the sources with [just](https://just.systems) 1.46 or
later, and `just test` runs the tests.

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
