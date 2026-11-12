#!/bin/bash

# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Prints the version of the sources this script belongs to, or the date of
# their commit in seconds since the epoch. A checkout asks git, while an
# archive that git archive created carries both in source-info. The version is
# the tag of the commit without a leading v, a tag followed by .r<count>.<hash>
# for the commits after it, or 0.r<count>.<hash> without a tag.

set -euo pipefail

# Status of a usage error, as for git and getopt
readonly USAGE_ERROR=2

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root_dir

if (($# != 1)) || [[ $1 != version && $1 != date ]]; then
    echo "usage: ${0##*/} version | date" >&2
    exit "${USAGE_ERROR}"
fi

describe="$(sed -n 's/^describe=//p' "${root_dir}/scripts/source-info")"
date="$(sed -n 's/^date=//p' "${root_dir}/scripts/source-info")"

# The placeholders remain in a checkout, since only git archive replaces them.
if [[ ${date} == "\$Format:"* ]]; then
    date="$(git -C "${root_dir}" log -1 --format=%ct)"

    if ! describe="$(git -C "${root_dir}" describe --tags 2> /dev/null)"; then
        count="$(git -C "${root_dir}" rev-list --count HEAD)"
        hash="$(git -C "${root_dir}" rev-parse --short HEAD)"
        describe="0-${count}-g${hash}"
    fi
elif [[ -z ${describe} ]]; then
    echo "error: expected a tag that describes the archived commit, got none" >&2
    exit 1
fi

if [[ $1 == date ]]; then
    echo "${date}"
    exit 0
fi

version="${describe#v}"

if [[ ${version} =~ ^(.*)-([0-9]+)-g([0-9a-f]+)$ ]]; then
    version="${BASH_REMATCH[1]}.r${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
fi

echo "${version}"
