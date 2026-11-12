# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Converts the AsciiDoc manual pages to troff below man and lints them.
man:
    ./scripts/build-man-pages.sh

test:
    ./tests/git-purge-branches.test.sh

# Checks that every file states its copyright and license as the REUSE
# specification requires.
lint:
    reuse lint
