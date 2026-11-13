#!/bin/bash

# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Installs the given components of git-purge-branches below a prefix, such as
# /usr/local or ~/.local, where git, man and the shells look for them, or
# removes them with --uninstall. A DESTDIR in the environment is prepended to
# the prefix, so that a package build can stage the files.

set -euo pipefail

# Status of a usage error, as for git and getopt
readonly USAGE_ERROR=2

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root_dir

function Usage()
{
    cat <<USAGE
usage: ${0##*/} [--uninstall] --prefix=<dir> <component>...

Components: script, man, bash, zsh, fish. man installs the manual pages that
build-man-pages.sh generated. --uninstall removes the files of the components
and keeps their directories, which other packages may share.
USAGE
}

prefix=
declare -i uninstall=0
components=()

while (($# > 0)); do
    case "$1" in
        --prefix=*)
            prefix="${1#--prefix=}"
            ;;
        --uninstall)
            uninstall=1
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
            components+=("$1")
            ;;
    esac
    shift
done

if [[ -z ${prefix} ]]; then
    echo "error: expected --prefix" >&2
    Usage >&2
    exit "${USAGE_ERROR}"
fi

if [[ ${prefix} != /* ]]; then
    echo "error: expected an absolute prefix, got '${prefix}'" >&2
    exit "${USAGE_ERROR}"
fi

destination="${DESTDIR:-}${prefix}"

# The modes, sources and targets of the files to install. All components are
# checked before any file is installed, so that a typo installs nothing.
modes=()
sources=()
targets=()

function Add()
{
    modes+=("$1")
    sources+=("${root_dir}/$2")
    targets+=("${destination}/$3")
}

for component in "${components[@]}"; do
    case "${component}" in
        script)
            Add 0755 git-purge-branches bin/git-purge-branches
            ;;
        man)
            Add 0644 man/man1/git-purge-branches.1 share/man/man1/git-purge-branches.1
            ;;
        bash)
            Add 0644 completion/git-purge-branches.bash \
                share/bash-completion/completions/git-purge-branches
            ;;
        zsh)
            Add 0644 completion/_git-purge-branches share/zsh/site-functions/_git-purge-branches
            ;;
        fish)
            Add 0644 completion/git-purge-branches.fish \
                share/fish/vendor_completions.d/git-purge-branches.fish
            ;;
        *)
            echo "error: unknown component '${component}'" >&2
            Usage >&2
            exit "${USAGE_ERROR}"
            ;;
    esac
done

# The script names the version it was installed from, which a package build
# passes in GIT_PURGE_BRANCHES_VERSION and a checkout or an archive knows.
staged_script="${root_dir}/git-purge-branches"

if ((! uninstall)) && [[ " ${components[*]} " == *" script "* ]]; then
    version="${GIT_PURGE_BRANCHES_VERSION:-}"

    if [[ -z ${version} ]]; then
        version="$("${root_dir}/scripts/version.sh" version)"
    fi

    staged_script="$(mktemp)"
    trap 'rm -f -- "${staged_script}"' EXIT
    sed "s/^stamped_version=.*/stamped_version=${version}/" "${root_dir}/git-purge-branches" >"${staged_script}"
fi

for index in "${!targets[@]}"; do
    file="${sources[index]}"

    if [[ ${file} == "${root_dir}/git-purge-branches" ]]; then
        file="${staged_script}"
    fi

    if ((uninstall)); then
        rm -f -- "${targets[index]}"
    else
        install -d "${targets[index]%/*}"
        install -m "${modes[index]}" "${file}" "${targets[index]}"
    fi
done
