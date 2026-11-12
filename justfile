# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Installation prefix, /usr/local with root privileges and ~/.local otherwise
default_prefix := if `id -u` == "0" { "/usr/local" } else { home_directory() / ".local" }

# Components of scripts/install.sh that the recipes install and uninstall
completions := "bash zsh fish"
components := "script man " + completions

# Converts the AsciiDoc manual pages to troff below man and lints them.
man:
    ./scripts/build-man-pages.sh

test:
    ./tests/git-purge-branches.test.sh

# Checks that every file states its copyright and license as REUSE requires,
# and the scripts and completions with the linters and formatters of their
# shells.
lint:
    reuse lint
    shellcheck --enable=all --shell=bash git-purge-branches scripts/*.sh tests/*.sh completion/*.bash
    zsh --no-exec completion/_git-purge-branches tests/complete.zsh
    fish --no-execute completion/*.fish
    fish_indent --check completion/*.fish

# Installs the script, its manual page and the completions below the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
install prefix=default_prefix: man
    ./scripts/install.sh --prefix={{ quote(prefix) }} {{ components }}

# Installs the completions of all shells below the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
install-completions prefix=default_prefix:
    ./scripts/install.sh --prefix={{ quote(prefix) }} {{ completions }}

# Installs the bash completion below the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
install-bash-completion prefix=default_prefix:
    ./scripts/install.sh --prefix={{ quote(prefix) }} bash

# Installs the zsh completion below the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
install-zsh-completion prefix=default_prefix:
    ./scripts/install.sh --prefix={{ quote(prefix) }} zsh

# Installs the fish completion below the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
install-fish-completion prefix=default_prefix:
    ./scripts/install.sh --prefix={{ quote(prefix) }} fish

# Removes the files that install puts below the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
uninstall prefix=default_prefix:
    ./scripts/install.sh --uninstall --prefix={{ quote(prefix) }} {{ components }}

# Removes the completions of all shells from the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
uninstall-completions prefix=default_prefix:
    ./scripts/install.sh --uninstall --prefix={{ quote(prefix) }} {{ completions }}

# Removes the bash completion from the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
uninstall-bash-completion prefix=default_prefix:
    ./scripts/install.sh --uninstall --prefix={{ quote(prefix) }} bash

# Removes the zsh completion from the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
uninstall-zsh-completion prefix=default_prefix:
    ./scripts/install.sh --uninstall --prefix={{ quote(prefix) }} zsh

# Removes the fish completion from the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
uninstall-fish-completion prefix=default_prefix:
    ./scripts/install.sh --uninstall --prefix={{ quote(prefix) }} fish
