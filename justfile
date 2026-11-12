# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Installation prefix, /usr/local with root privileges and ~/.local otherwise
default_prefix := if `id -u` == "0" { "/usr/local" } else { home_directory() / ".local" }

# Converts the AsciiDoc manual pages to troff below man and lints them.
man:
    ./scripts/build-man-pages.sh

test:
    ./tests/git-purge-branches.test.sh

# Checks that every file states its copyright and license as REUSE requires.
lint:
    reuse lint

# Installs the script, its manual page and the completions below the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
install prefix=default_prefix: man
    ./scripts/install.sh --prefix={{ quote(prefix) }} script man bash zsh fish

# Installs the completions of all shells below the prefix.
[arg("prefix", long="prefix", help="installation prefix, /usr/local for root and ~/.local otherwise")]
install-completions prefix=default_prefix:
    ./scripts/install.sh --prefix={{ quote(prefix) }} bash zsh fish

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
