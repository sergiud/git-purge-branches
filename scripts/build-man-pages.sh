#!/bin/bash

# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Converts the AsciiDoc manual pages to troff below man, where man finds them
# while the project directory is in PATH, and lints the result. groff exits
# with 0 even if it warns, so any diagnostic fails the script.

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root_dir
readonly man_dir="${root_dir}/man/man1"

asciidoctor --backend manpage --failure-level WARN --destination-dir "${man_dir}" "${root_dir}"/doc/man/*.adoc

for page in "${man_dir}"/*.1; do
    diagnostics="$(groff -man -rCHECKSTYLE=3 -ww -z "${page}" 2>&1)"
    if [[ -n ${diagnostics} ]]; then
        echo "error: groff diagnostics for ${page}:" >&2
        echo "${diagnostics}" >&2
        exit 1
    fi
done
