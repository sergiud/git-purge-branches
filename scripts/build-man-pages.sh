#!/bin/bash

# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Converts the AsciiDoc manual pages to troff below man, where man finds them
# while the project directory is in PATH, and lints the result. groff exits
# with 0 even if it warns, so any diagnostic fails the script. With
# --html=<dir>, renders the manual page as index.html into the directory
# instead, as GitHub Pages serves it.

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root_dir
readonly man_dir="${root_dir}/man/man1"

html_dir=

if [[ $# -eq 1 && $1 == --html=* ]]; then
    html_dir="${1#--html=}"
elif (($# != 0)); then
    echo "usage: ${0##*/} [--html=<dir>]" >&2
    exit 2
fi

# The pages show the date of the commit unless a package build sets another,
# so that every build of a commit yields the same pages.
if [[ -z ${SOURCE_DATE_EPOCH:-} ]]; then
    SOURCE_DATE_EPOCH="$("${root_dir}/scripts/version.sh" date)"
    export SOURCE_DATE_EPOCH
fi

# The extensions provide the macro linkgit of the documentation of Git and the
# links of the anchors of options.
readonly asciidoctor=(asciidoctor --require "${root_dir}/doc/man/extensions.rb" --failure-level WARN)

# Only HTML highlights the examples, so that manual pages build without Rouge,
# and names the version, which the published site of all releases switches
# between.
if [[ -n ${html_dir} ]]; then
    version="$("${root_dir}/scripts/version.sh" version)"
    "${asciidoctor[@]}" --backend html5 --attribute source-highlighter=rouge \
        --attribute rouge-css=class --attribute revnumber="${version}" \
        --out-file "${html_dir}/index.html" "${root_dir}/doc/man/git-purge-branches.adoc"
    exit 0
fi

"${asciidoctor[@]}" --backend manpage --destination-dir "${man_dir}" "${root_dir}"/doc/man/*.adoc

for page in "${man_dir}"/*.1; do
    diagnostics="$(groff -man -rCHECKSTYLE=3 -ww -z "${page}" 2>&1)"
    if [[ -n ${diagnostics} ]]; then
        echo "error: groff diagnostics for ${page}:" >&2
        echo "${diagnostics}" >&2
        exit 1
    fi
done
