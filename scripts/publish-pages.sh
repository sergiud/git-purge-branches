#!/bin/bash

# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Adds the site of a release, which just pages renders, to the published site
# of all releases, such as a checkout of the branch gh-pages. The release keeps
# its site below <version>/, which later releases leave as it is, and the root
# serves the site of the release published last. versions.json lists the
# versions, the one published last first.

set -euo pipefail

# Status of a usage error, as for git and getopt
readonly USAGE_ERROR=2

function Usage()
{
    cat <<USAGE
usage: ${0##*/} --version=<version> <site> <published>
USAGE
}

version=
arguments=()

while (($# > 0)); do
    case "$1" in
        --version=*)
            version="${1#--version=}"
            ;;
        -h | --help)
            Usage
            exit 0
            ;;
        -*)
            echo "error: unknown option '$1'" >&2
            Usage >&2
            exit "${USAGE_ERROR}"
            ;;
        *)
            arguments+=("$1")
            ;;
    esac
    shift
done

# A version names a directory of the published site.
if [[ ! ${version} =~ ^[0-9][0-9A-Za-z.+~]*$ ]]; then
    echo "error: expected a version that starts with a digit and holds no slash, got '${version}'" >&2
    exit "${USAGE_ERROR}"
fi

if ((${#arguments[@]} != 2)); then
    echo "error: expected the site and the published site, got ${#arguments[@]} directories" >&2
    Usage >&2
    exit "${USAGE_ERROR}"
fi

readonly site="${arguments[0]}"
readonly published="${arguments[1]}"

mkdir -p -- "${published}"
rm -rf -- "${published:?}/${version}"
cp -R -- "${site}" "${published}/${version}"
cp -R -- "${site}"/. "${published}"

# versions.txt holds the versions, the one published last first, from which
# versions.json follows.
versions=("${version}")

if [[ -f ${published}/versions.txt ]]; then
    while IFS= read -r line; do
        if [[ ${line} != "${version}" ]]; then
            versions+=("${line}")
        fi
    done <"${published}/versions.txt"
fi

printf '%s\n' "${versions[@]}" >"${published}/versions.txt"

json="$(printf '"%s",' "${versions[@]}")"
echo "[${json%,}]" >"${published}/versions.json"
