#!/bin/bash

# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Installs a release of git-purge-branches from GitHub below a prefix, or
# removes it again, without a checkout:
#
#   curl -fsSL https://sergiud.github.io/git-purge-branches/install.sh | bash
#   curl -fsSL … | bash -s -- --prefix=/usr/local --version=1.2.3 --uninstall

set -euo pipefail

# Status of a usage error, as for git and getopt
readonly USAGE_ERROR=2

function Usage()
{
    cat <<USAGE
usage: install.sh [--prefix=<dir>] [--version=<version>] [--uninstall]

Installs the latest release, or the given one, below the prefix, which is
/usr/local for root and ~/.local otherwise. The tarball of the release must
match its checksum. --uninstall removes the files of the release again.
USAGE
}

prefix=
version=
declare -i uninstall=0

while (($# > 0)); do
    case "$1" in
        --prefix=*)
            prefix="${1#--prefix=}"
            ;;
        --version=*)
            version="${1#--version=}"
            ;;
        --uninstall)
            uninstall=1
            ;;
        -h | --help)
            Usage
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1'" >&2
            Usage >&2
            exit "${USAGE_ERROR}"
            ;;
    esac
    shift
done

readonly name=git-purge-branches
# The release page of GitHub, which tests replace by a server of their own
readonly releases="${GIT_PURGE_BRANCHES_RELEASES:-https://github.com/sergiud/${name}/releases}"

if [[ -z ${prefix} ]]; then
    user_id="$(id -u)"

    if ((user_id == 0)); then
        prefix=/usr/local
    else
        prefix="${HOME}/.local"
    fi
fi

if [[ ${prefix} != /* ]]; then
    echo "error: expected an absolute prefix, got '${prefix}'" >&2
    exit "${USAGE_ERROR}"
fi

# GitHub redirects the latest release to its page, whose URL ends in its tag,
# or to the list of releases if all of them are prereleases.
if [[ -z ${version} ]]; then
    if ! latest="$(curl -fsS -o /dev/null -w '%{redirect_url}' "${releases}/latest")" ||
        [[ -z ${latest} ]]; then
        echo "error: failed to find the latest release at ${releases}" >&2
        exit 1
    fi

    if [[ ${latest} != */releases/tag/v* ]]; then
        echo "error: found no release that is not a prerelease at ${releases}, which --version selects" >&2
        exit 1
    fi

    version="${latest##*/releases/tag/v}"
fi

readonly tarball="${name}-${version}.tar.gz"

downloads="$(mktemp -d)"
readonly downloads
trap 'rm -rf -- "${downloads}"' EXIT

for asset in "${tarball}" SHA256SUMS; do
    if ! curl -fsSL -o "${downloads}/${asset}" "${releases}/download/v${version}/${asset}"; then
        echo "error: failed to download ${asset} of release ${version}" >&2
        exit 1
    fi
done

# sha256sum fails for a tarball without a line of its own as well.
grep -F "  ${tarball}" "${downloads}/SHA256SUMS" >"${downloads}/checksum" || true

if ! (cd "${downloads}" && sha256sum --check --status checksum 2>/dev/null); then
    echo "error: expected the checksum of ${tarball} in SHA256SUMS" >&2
    exit 1
fi

if ((uninstall)); then
    # The files of the release below its top-level directory
    tar --list --gzip --file="${downloads}/${tarball}" >"${downloads}/files"

    while IFS= read -r path; do
        if [[ ${path} != */ && ${path} == */* ]]; then
            rm -f -- "${prefix}/${path#*/}"
        fi
    done <"${downloads}/files"

    echo "removed ${name} ${version} from ${prefix}"
    exit 0
fi

if ! mkdir -p -- "${prefix}" 2>/dev/null ||
    ! tar --extract --gzip --file="${downloads}/${tarball}" --directory="${prefix}" \
        --strip-components=1 2>/dev/null; then
    echo "error: failed to install ${name} ${version} below '${prefix}'" >&2
    exit 1
fi

echo "installed ${name} ${version} below ${prefix}"
