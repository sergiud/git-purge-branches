#!/bin/bash

# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Tests for git-purge-branches. Each test runs the script in a new repository
# with the global and system Git configuration disabled, so the user's
# configuration cannot change the outcome.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly SCRIPT="${ROOT_DIR}/git-purge-branches"
readonly COMPLETION="${ROOT_DIR}/completion/git-purge-branches.bash"
readonly ZSH_COMPLETION="${ROOT_DIR}/completion/_git-purge-branches"
readonly FISH_COMPLETION="${ROOT_DIR}/completion/git-purge-branches.fish"
# The manual page that the man recipe generates
readonly MAN_PAGE="${ROOT_DIR}/man/man1/git-purge-branches.1"
# Paths of the installed files relative to the prefix
readonly INSTALLED_SCRIPT=bin/git-purge-branches
readonly INSTALLED_MAN_PAGE=share/man/man1/git-purge-branches.1
readonly INSTALLED_COMPLETION=share/bash-completion/completions/git-purge-branches
readonly INSTALLED_ZSH_COMPLETION=share/zsh/site-functions/_git-purge-branches
readonly INSTALLED_FISH_COMPLETION=share/fish/vendor_completions.d/git-purge-branches.fish
# The main script of bash-completion, which loads completions on demand
BASH_COMPLETION="$(pkg-config --variable=completionsdir bash-completion)/../bash_completion"
readonly BASH_COMPLETION
# Status of git when it runs outside a repository
readonly GIT_NOT_A_REPOSITORY=128
# Status of the script for invalid options or arguments
readonly USAGE_ERROR=2
# Seconds after which a run counts as hung. A run of the script takes
# milliseconds and a package build seconds, but the first package build on a
# runner of GitHub took close to a minute, so the limit only ends runs that
# never finish.
readonly HANG_TIMEOUT=600

failures=0
skipped=0
tests=0

function Git()
{
    git -C "${repo}" "$@"
}

function SetUp()
{
    sandbox="$(mktemp -d)"
    repo="${sandbox}/repo"
    server_pid=

    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=test
    export GIT_AUTHOR_EMAIL=test@example.com
    export GIT_COMMITTER_NAME=test
    export GIT_COMMITTER_EMAIL=test@example.com
    export GIT_CEILING_DIRECTORIES="${sandbox}"

    git init -q -b master "${repo}"
    Git commit -q --allow-empty -m initial
}

function TearDown()
{
    if [[ -n ${server_pid} ]]; then
        kill "${server_pid}"
        wait "${server_pid}"
        server_pid=
    fi

    rm -Rf "${sandbox}"
}

# Runs the script under test in the given directory with the remaining
# arguments and stores its exit status, which is that of timeout if the run
# hangs.
function RunPurgeIn()
{
    local directory="$1"
    local input=/dev/null
    shift

    # The answers to a prompt, which a test writes to the file stdin, or none.
    if [[ -f ${sandbox}/stdin ]]; then
        input="${sandbox}/stdin"
    fi

    (cd "${directory}" && timeout "${HANG_TIMEOUT}" /bin/bash "${SCRIPT}" "$@") \
        <"${input}" >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
}

function RunPurge()
{
    RunPurgeIn "${repo}" "$@"
}

# Creates a branch with a commit that the current branch lacks.
function CreateUnmergedBranch()
{
    local name="$1"

    Git switch -q -c "${name}"
    Git commit -q --allow-empty -m "${name}"
    Git switch -q -
}

# Commits a new file with the given name on the current branch.
function CommitFile()
{
    local name="$1"

    echo "${name}" >"${repo}/${name}"
    Git add "${name}"
    Git commit -q -m "${name}"
}

# Creates a branch with a commit that the target lacks and copies the commit
# onto the target, as a rebase and merge on a remote does. A commit on the
# target before the copy gives the copy another hash.
function CreateRebasedBranch()
{
    local name="$1"
    local target="$2"

    Git switch -q -c "${name}"
    CommitFile "${name}"
    Git switch -q "${target}"
    CommitFile "${target}-${name}"
    Git cherry-pick "${name}" >/dev/null
    Git switch -q master
}

function Fail()
{
    echo "    $*"
    test_failed=1
}

# Marks the running test as skipped for the given reason. With
# REQUIRE_ALL_TESTS set, as in CI, the test fails instead, so that a missing
# tool cannot silently disable it.
function Skip()
{
    if [[ -n ${REQUIRE_ALL_TESTS:-} ]]; then
        Fail "$*"
    else
        echo "    $*"
        test_skipped=1
    fi
}

# Skips the running test and returns 1 unless all the given commands exist.
function RequireCommands()
{
    local command

    for command in "$@"; do
        if ! command -v "${command}" >/dev/null; then
            Skip "skipped since ${command} is missing"
            return 1
        fi
    done
}

function ExpectStatus()
{
    local expected="$1"

    if [[ ${status} -ne ${expected} ]]; then
        Fail "expected exit status ${expected}, got ${status}, stderr: '$(<"${sandbox}/stderr")'"
    fi
}

function ExpectBranches()
{
    local expected="$*"
    local actual
    actual="$(Git for-each-ref --format='%(refname:lstrip=2)' refs/heads/)"
    actual="${actual//$'\n'/ }"

    if [[ ${actual} != "${expected}" ]]; then
        Fail "expected branches '${expected}', got '${actual}'"
    fi
}

function ExpectStdout()
{
    local expected="$*"
    local actual
    actual="$(<"${sandbox}/stdout")"
    actual="${actual//$'\n'/ }"

    if [[ ${actual} != "${expected}" ]]; then
        Fail "expected stdout '${expected}', got '${actual}'"
    fi
}

function ExpectStdoutContains()
{
    local expected="$1"

    if ! grep -qF -- "${expected}" "${sandbox}/stdout"; then
        Fail "expected stdout to contain '${expected}', got '$(<"${sandbox}/stdout")'"
    fi
}

function ExpectStderrContains()
{
    local expected="$1"

    if ! grep -qF -- "${expected}" "${sandbox}/stderr"; then
        Fail "expected stderr to contain '${expected}', got '$(<"${sandbox}/stderr")'"
    fi
}

function TestDeletesMergedBranch()
{
    Git branch feature
    RunPurge
    ExpectStatus 0
    ExpectBranches master
}

function TestSucceedsWithoutMergedBranches()
{
    RunPurge
    ExpectStatus 0
    ExpectBranches master
}

function TestKeepsUnmergedBranch()
{
    CreateUnmergedBranch topic
    Git branch feature
    RunPurge
    ExpectStatus 0
    ExpectBranches master topic
}

function TestKeepsBranchOfOtherWorktree()
{
    Git branch elsewhere
    Git branch feature
    Git worktree add -q "${sandbox}/worktree" elsewhere
    RunPurge
    ExpectStatus 0
    ExpectBranches elsewhere master
}

function TestKeepsCurrentBranchOfLinkedWorktree()
{
    Git branch elsewhere
    Git worktree add -q "${sandbox}/worktree" elsewhere
    RunPurgeIn "${sandbox}/worktree"
    ExpectStatus 0
    ExpectBranches elsewhere master
}

function TestDeletesBranchWithPlusInName()
{
    Git branch 'c++'
    RunPurge
    ExpectStatus 0
    ExpectBranches master
}

function TestDeletesBranchSharingNameWithTag()
{
    Git branch v1
    Git tag v1
    RunPurge
    ExpectStatus 0
    ExpectBranches master
}

# git branch -d refuses a branch whose upstream lacks its commits, even if
# HEAD contains them, which keeps work that was never pushed.
function TestKeepsBranchAheadOfUpstream()
{
    Git config remote.origin.url "${repo}"
    Git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    Git update-ref refs/remotes/origin/feature HEAD
    Git commit -q --allow-empty -m unpushed
    Git branch feature
    Git config branch.feature.remote origin
    Git config branch.feature.merge refs/heads/feature
    RunPurge
    ExpectStatus 1
    ExpectBranches feature master
}

function TestIgnoresColorConfiguration()
{
    Git config color.branch always
    Git config color.ui always
    Git branch feature
    RunPurge
    ExpectStatus 0
    ExpectBranches master
}

function TestKeepsBranchGivenAsCommit()
{
    Git branch feature
    Git branch merged
    RunPurge feature
    ExpectStatus 0
    ExpectBranches feature master
}

function TestKeepsBranchGivenAsFullRefName()
{
    Git branch feature
    Git branch merged
    RunPurge refs/heads/feature
    ExpectStatus 0
    ExpectBranches feature master
}

# A tag names no branch, so a branch at the same commit is deleted.
function TestDeletesBranchAtGivenTag()
{
    Git tag v1
    Git branch release
    RunPurge v1
    ExpectStatus 0
    ExpectBranches master
}

function TestDeletesBranchNamedLikeGivenTag()
{
    Git tag v1
    Git branch refs/tags/v1
    RunPurge v1
    ExpectStatus 0
    ExpectBranches master
}

function TestKeepsRebasedBranchByDefault()
{
    CreateRebasedBranch feature master
    RunPurge
    ExpectStatus 0
    ExpectBranches feature master
}

function TestDeletesRebasedBranchWithEquivalent()
{
    CreateRebasedBranch feature master
    RunPurge --equivalent
    ExpectStatus 0
    ExpectBranches master
}

function TestDeletesBranchRebasedOntoGivenCommit()
{
    Git branch release
    CreateRebasedBranch feature release
    RunPurge -e release
    ExpectStatus 0
    ExpectBranches master release
}

function TestDeletesRebasedBranchFromSubdirectoryWithEquivalent()
{
    mkdir "${repo}/subdirectory"
    CreateRebasedBranch feature master
    RunPurgeIn "${repo}/subdirectory" --equivalent
    ExpectStatus 0
    ExpectBranches master
}

function TestKeepsPartlyRebasedBranchWithEquivalent()
{
    CreateRebasedBranch feature master
    Git switch -q feature
    CommitFile unpicked
    Git switch -q master
    RunPurge --equivalent
    ExpectStatus 0
    ExpectBranches feature master
}

# git cherry treats every empty commit as equivalent to any other.
function TestKeepsBranchOfEmptyCommitsWithEquivalent()
{
    CreateUnmergedBranch topic
    Git commit -q --allow-empty -m other
    RunPurge --equivalent
    ExpectStatus 0
    ExpectBranches master topic
}

# git cherry omits merge commits, so changes made in a merge, such as a
# conflict resolution, have no equivalent it could check.
function TestKeepsBranchWithChangingMergeWithEquivalent()
{
    Git branch side
    Git switch -q -c feature
    CommitFile feature
    Git switch -q side
    CommitFile side
    Git switch -q feature
    Git merge -q --no-commit side >/dev/null 2>&1
    CommitFile resolution
    Git switch -q master
    CommitFile master-feature
    Git cherry-pick side feature^ >/dev/null
    Git branch -D -q side
    RunPurge --equivalent
    ExpectStatus 0
    ExpectBranches feature master
}

function TestKeepsRebasedBranchOfOtherWorktreeWithEquivalent()
{
    CreateRebasedBranch feature master
    Git worktree add -q "${sandbox}/worktree" feature
    RunPurge --equivalent
    ExpectStatus 0
    ExpectBranches feature master
}

function TestDeletesRebasedBranchWhenMergedBranchIsRefused()
{
    Git config remote.origin.url "${repo}"
    Git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    Git update-ref refs/remotes/origin/feature HEAD
    Git commit -q --allow-empty -m unpushed
    Git branch feature
    Git config branch.feature.remote origin
    Git config branch.feature.merge refs/heads/feature
    CreateRebasedBranch rebased master
    RunPurge --equivalent
    ExpectStatus 1
    ExpectBranches feature master
}

# A stale lock of the branch makes its deletion fail.
function TestReportsFailureToDeleteRebasedBranch()
{
    CreateRebasedBranch rebased master
    touch "${repo}/.git/refs/heads/rebased.lock"
    RunPurge --equivalent
    ExpectStatus 1
    ExpectBranches master rebased
}

# Runs the commands that the restore hint in the output of the script prints,
# one per line after its header.
function RunRestoreHint()
{
    local line
    local -a command

    while IFS= read -r line; do
        if [[ ${line} == "git branch "* ]]; then
            read -ra command <<<"${line}"
            Git "${command[@]:1}"
        fi
    done <"${sandbox}/stdout"
}

function TestPrintsHowToRestoreDeletedBranches()
{
    local feature
    local topic
    local restored

    Git branch feature
    Git commit -q --allow-empty -m next
    Git branch topic
    feature="$(Git rev-parse feature)"
    topic="$(Git rev-parse topic)"
    RunPurge
    ExpectStatus 0
    ExpectBranches master
    ExpectStdoutContains "Restore the deleted branches with:"
    RunRestoreHint
    ExpectBranches feature master topic
    restored="$(Git rev-parse feature topic)"
    ExpectLines "${restored}" "${feature}"$'\n'"${topic}"
}

# git branch -d refuses a branch that is not merged into its upstream, which
# remains and needs no restoring.
function TestRestoreHintOmitsRefusedBranches()
{
    local master

    Git config remote.origin.url "${repo}"
    Git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    Git update-ref refs/remotes/origin/feature HEAD
    Git commit -q --allow-empty -m unpushed
    Git branch feature
    Git config branch.feature.remote origin
    Git config branch.feature.merge refs/heads/feature
    Git branch other
    master="$(Git rev-parse master)"
    RunPurge
    ExpectStatus 1
    ExpectStdoutContains "git branch other ${master}"

    if grep -q '^git branch feature ' "${sandbox}/stdout"; then
        Fail "expected no restore command of the remaining branch feature"
    fi
}

function TestPrintsNoRestoreHintWithoutDeletedBranches()
{
    Git branch feature
    RunPurge --dry-run
    ExpectStatus 0
    ExpectStdout $'feature\tmerged'
    CreateUnmergedBranch topic
    RunPurge feature
    ExpectStatus 0
    ExpectStdout ""
}

# Creates the branch feature with a commit of its own and pushes it to origin,
# whose default branch main then merges it, as a pull request does. The
# current branch master lacks the commit.
function CreateBranchMergedIntoOrigin()
{
    Git config remote.origin.url "${repo}"
    Git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    CreateUnmergedBranch feature
    Git update-ref refs/remotes/origin/feature feature
    Git config branch.feature.remote origin
    Git config branch.feature.merge refs/heads/feature
    Git update-ref refs/remotes/origin/main feature
    Git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

function TestDefaultsToDefaultBranchOfOrigin()
{
    CreateBranchMergedIntoOrigin
    RunPurge
    ExpectStatus 0
    ExpectBranches master
}

function TestGivenCommitOverridesDefaultBranchOfOrigin()
{
    CreateBranchMergedIntoOrigin
    Git branch merged
    RunPurge HEAD
    ExpectStatus 0
    ExpectBranches feature master
}

function TestDryRunDefaultsToDefaultBranchOfOrigin()
{
    CreateBranchMergedIntoOrigin
    RunPurge --dry-run
    ExpectStatus 0
    ExpectStdout $'feature\tmerged'
    ExpectBranches feature master
}

# Writes the given answer to the prompt of the script to its standard input.
function Answer()
{
    printf '%s\n' "$1" >"${sandbox}/stdin"
}

function TestInteractiveDeletesAfterYes()
{
    Git branch feature
    Answer y
    RunPurge --interactive
    ExpectStatus 0
    ExpectStdoutContains $'feature\tmerged'
    ExpectStderrContains "Delete these branches? [y/N] "
    ExpectBranches master
}

function TestInteractiveAcceptsYesInAnyCase()
{
    Git branch feature
    Answer YES
    RunPurge -i
    ExpectStatus 0
    ExpectBranches master
}

function TestInteractiveKeepsBranchesAfterNo()
{
    Git branch feature
    Answer n
    RunPurge --interactive
    ExpectStatus 0
    ExpectStdout $'feature\tmerged'
    ExpectBranches feature master
}

function TestInteractiveKeepsBranchesWithoutAnswer()
{
    Git branch feature
    RunPurge --interactive
    ExpectStatus 0
    ExpectBranches feature master
}

function TestInteractiveAsksNothingWithoutBranches()
{
    CreateUnmergedBranch topic
    Answer y
    RunPurge --interactive
    ExpectStatus 0
    ExpectStdout ""

    if [[ -s ${sandbox}/stderr ]]; then
        Fail "expected no prompt, got '$(<"${sandbox}/stderr")'"
    fi
}

# A dry run deletes nothing and therefore asks nothing.
function TestInteractiveDryRunAsksNothing()
{
    Git branch feature
    Answer y
    RunPurge -ni
    ExpectStatus 0
    ExpectStdout $'feature\tmerged'
    ExpectBranches feature master

    if [[ -s ${sandbox}/stderr ]]; then
        Fail "expected no prompt, got '$(<"${sandbox}/stderr")'"
    fi
}

# A dry run prints each branch and the reason it would be deleted, separated
# by a tab.
function TestDryRunListsMergedBranches()
{
    Git branch feature
    Git branch other
    RunPurge --dry-run
    ExpectStatus 0
    ExpectStdout $'feature\tmerged' $'other\tmerged'
    ExpectBranches feature master other
}

function TestDryRunListsRebasedBranchesWithEquivalent()
{
    Git branch merged
    CreateRebasedBranch rebased master
    RunPurge -n -e
    ExpectStatus 0
    ExpectStdout $'merged\tmerged' $'rebased\tequivalent'
    ExpectBranches master merged rebased
}

function TestDryRunOmitsRebasedBranchesByDefault()
{
    Git branch merged
    CreateRebasedBranch rebased master
    RunPurge -n
    ExpectStatus 0
    ExpectStdout $'merged\tmerged'
    ExpectBranches master merged rebased
}

# Runs a dry run with the given bundle of -e and -n.
function ExpectBundledOptionsAccepted()
{
    local options="$1"

    Git branch merged
    CreateRebasedBranch rebased master
    RunPurge "${options}"
    ExpectStatus 0
    ExpectStdout $'merged\tmerged' $'rebased\tequivalent'
    ExpectBranches master merged rebased
}

function TestAcceptsBundledShortOptions()
{
    ExpectBundledOptionsAccepted -en
}

function TestAcceptsBundledShortOptionsInEitherOrder()
{
    ExpectBundledOptionsAccepted -ne
}

function TestAcceptsOptionsAfterCommit()
{
    Git branch release
    CreateRebasedBranch feature release
    RunPurge release -e
    ExpectStatus 0
    ExpectBranches master release
}

function TestHelpPrintsUsage()
{
    Git branch feature
    RunPurge --help
    ExpectStatus 0
    ExpectBranches feature master

    if ! grep -qF -- '--equivalent' "${sandbox}/stdout"; then
        Fail "expected usage with --equivalent on stdout, got '$(<"${sandbox}/stdout")'"
    fi
}

function TestRejectsUnknownOption()
{
    Git branch feature
    RunPurge --force
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: unknown option '--force'"
    ExpectBranches feature master
}

function TestRejectsUnknownOptionInBundle()
{
    Git branch feature
    RunPurge -ex
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: unknown option '-x'"
    ExpectBranches feature master
}

function TestRejectsSecondCommit()
{
    Git branch feature
    RunPurge HEAD feature
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: expected at most 1 commit, got 2"
    ExpectBranches feature master
}

function TestKeepsMergedBranchExemptByConfig()
{
    Git branch feature
    Git branch other
    Git config branch.feature.deleteMerged false
    RunPurge
    ExpectStatus 0
    ExpectBranches feature master
}

function TestKeepsRebasedBranchExemptByConfig()
{
    CreateRebasedBranch feature master
    Git config branch.feature.deleteMerged false
    RunPurge --equivalent
    ExpectStatus 0
    ExpectBranches feature master
}

# Points the default branch of the given remote at the local branch of the
# same name, as a clone records it.
function SetRemoteDefaultBranch()
{
    local remote="$1"
    local branch="$2"

    Git update-ref "refs/remotes/${remote}/${branch}" "${branch}"
    Git symbolic-ref "refs/remotes/${remote}/HEAD" "refs/remotes/${remote}/${branch}"
}

# A topic branch contains the branch it started from, which therefore counts
# as merged.
function TestKeepsDefaultBranchOfRemote()
{
    Git branch develop
    Git switch -q -c topic
    Git commit -q --allow-empty -m topic
    SetRemoteDefaultBranch origin master
    RunPurge HEAD
    ExpectStatus 0
    ExpectBranches master topic
}

function TestKeepsDefaultBranchOfEachRemote()
{
    Git branch develop
    Git branch other
    Git switch -q -c topic
    Git commit -q --allow-empty -m topic
    SetRemoteDefaultBranch origin master
    SetRemoteDefaultBranch upstream develop
    RunPurge HEAD
    ExpectStatus 0
    ExpectBranches develop master topic
}

# A pattern matches the whole name of a branch, as a glob of the shell does.
function TestKeepsBranchesMatchingKeepPatterns()
{
    Git branch develop
    Git branch release/1.0
    Git branch prerelease/1.0
    Git config --add purge-branches.keep develop
    Git config --add purge-branches.keep 'release/*'
    RunPurge
    ExpectStatus 0
    ExpectBranches develop master release/1.0
}

function TestKeepsRebasedBranchMatchingKeepPattern()
{
    CreateRebasedBranch release-1.0 master
    Git config purge-branches.keep 'release-*'
    RunPurge --equivalent
    ExpectStatus 0
    ExpectBranches master release-1.0
}

function TestDryRunOmitsProtectedBranches()
{
    Git branch develop
    Git branch merged
    Git switch -q -c topic
    Git commit -q --allow-empty -m topic
    SetRemoteDefaultBranch origin master
    Git config purge-branches.keep develop
    RunPurge --dry-run HEAD
    ExpectStatus 0
    ExpectStdout $'merged\tmerged'
}

function TestDryRunOmitsExemptBranches()
{
    Git branch merged
    Git branch exempt
    CreateRebasedBranch rebased master
    Git config branch.exempt.deleteMerged false
    Git config branch.rebased.deleteMerged false
    RunPurge --dry-run --equivalent
    ExpectStatus 0
    ExpectStdout $'merged\tmerged'
    ExpectBranches exempt master merged rebased
}

function TestDeletesBranchWithDeleteMergedTrue()
{
    Git branch feature
    Git config branch.feature.deleteMerged true
    RunPurge
    ExpectStatus 0
    ExpectBranches master
}

# Git accepts several spellings of a boolean.
function TestKeepsBranchExemptByConfigSpelledNo()
{
    Git branch feature
    Git config branch.feature.deleteMerged no
    RunPurge
    ExpectStatus 0
    ExpectBranches feature master
}

# The last dot of the key separates the variable from a branch name that
# contains dots.
function TestKeepsExemptBranchWithDotInName()
{
    Git branch release.1
    Git config branch.release.1.deleteMerged false
    RunPurge
    ExpectStatus 0
    ExpectBranches master release.1
}

function TestKeepsExemptBranchWithSlashInName()
{
    Git branch topic/feature
    Git config branch.topic/feature.deleteMerged false
    RunPurge
    ExpectStatus 0
    ExpectBranches master topic/feature
}

function TestReportsInvalidDeleteMerged()
{
    Git branch feature
    Git branch other
    Git config branch.feature.deleteMerged maybe
    RunPurge
    ExpectStatus "${GIT_NOT_A_REPOSITORY}"
    ExpectStderrContains "bad boolean config value 'maybe'"
    ExpectBranches feature master other
}

function TestReportsInvalidCommit()
{
    Git branch feature
    RunPurge missing
    ExpectStatus "${GIT_NOT_A_REPOSITORY}"
    ExpectStderrContains "error: failed to list branches"
    ExpectBranches feature master
}

function TestReportsFailureOutsideRepository()
{
    mkdir "${sandbox}/plain"
    RunPurgeIn "${sandbox}/plain"
    ExpectStatus "${GIT_NOT_A_REPOSITORY}"
    ExpectStderrContains "error: failed to list branches"
}

# Makes id report the given user ID to the recipes that RunJust runs, so that
# the default prefix does not depend on the user who runs the tests.
function FakeUserId()
{
    local uid="$1"

    mkdir -p "${sandbox}/fake-bin"
    printf '#!/bin/sh\necho %s\n' "${uid}" >"${sandbox}/fake-bin/id"
    chmod +x "${sandbox}/fake-bin/id"
}

# Runs the given recipe of the justfile with its arguments and stores its exit
# status. The home directory is in the sandbox, so that the default prefix of a
# user never points to the real one.
function RunJustIn()
{
    local directory="$1"
    shift

    (HOME="${sandbox}/home" PATH="${sandbox}/fake-bin:${PATH}" \
        timeout "${HANG_TIMEOUT}" just --justfile "${directory}/justfile" "$@") \
        >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
}

function RunJust()
{
    RunJustIn "${ROOT_DIR}" "$@"
}

function RunInstallScript()
{
    timeout "${HANG_TIMEOUT}" "${ROOT_DIR}/scripts/install.sh" "$@" \
        >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
}

function ExpectInstalledFile()
{
    local path="$1"
    local mode="$2"
    local source="$3"
    local actual_mode

    if [[ ! -f ${path} ]]; then
        Fail "expected installed file '${path}'"
        return
    fi

    actual_mode="$(stat --format=%a "${path}")"

    if [[ ${actual_mode} != "${mode}" ]]; then
        Fail "expected mode ${mode} of '${path}', got ${actual_mode}"
    fi

    if ! cmp --quiet "${path}" "${source}"; then
        Fail "expected '${path}' to equal '${source}'"
    fi
}

function ExpectExists()
{
    local path="$1"

    if [[ ! -e ${path} ]]; then
        Fail "expected '${path}' to exist"
    fi
}

function ExpectNotInstalled()
{
    local path="$1"

    if [[ -e ${path} ]]; then
        Fail "expected no file '${path}'"
    fi
}

function ExpectScriptAndManPageInstalled()
{
    local prefix="$1"

    ExpectInstalledFile "${prefix}/${INSTALLED_SCRIPT}" 755 "${SCRIPT}"
    ExpectInstalledFile "${prefix}/${INSTALLED_MAN_PAGE}" 644 "${MAN_PAGE}"
}

function ExpectCompletionsInstalled()
{
    local prefix="$1"

    ExpectInstalledFile "${prefix}/${INSTALLED_COMPLETION}" 644 "${COMPLETION}"
    ExpectInstalledFile "${prefix}/${INSTALLED_ZSH_COMPLETION}" 644 "${ZSH_COMPLETION}"
    ExpectInstalledFile "${prefix}/${INSTALLED_FISH_COMPLETION}" 644 "${FISH_COMPLETION}"
}

function TestInstallInstallsAllBelowPrefix()
{
    RunJust install --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectScriptAndManPageInstalled "${sandbox}/prefix"
    ExpectCompletionsInstalled "${sandbox}/prefix"
}

function TestInstallAcceptsPrefixWithSpace()
{
    RunJust install-completions --prefix="${sandbox}/with space"
    ExpectStatus 0
    ExpectCompletionsInstalled "${sandbox}/with space"
}

function TestInstallDefaultsToLocalOfHomeWithoutRoot()
{
    FakeUserId 1000
    RunJust install
    ExpectStatus 0
    ExpectScriptAndManPageInstalled "${sandbox}/home/.local"
    ExpectCompletionsInstalled "${sandbox}/home/.local"
}

# DESTDIR keeps the default prefix of root from pointing to the real one.
function TestInstallDefaultsToUsrLocalWithRoot()
{
    FakeUserId 0
    DESTDIR="${sandbox}/stage" RunJust install
    ExpectStatus 0
    ExpectScriptAndManPageInstalled "${sandbox}/stage/usr/local"
    ExpectCompletionsInstalled "${sandbox}/stage/usr/local"
}

function TestInstallStagesBelowDestdir()
{
    DESTDIR="${sandbox}/stage" RunJust install --prefix=/opt/purge
    ExpectStatus 0
    ExpectScriptAndManPageInstalled "${sandbox}/stage/opt/purge"
    ExpectCompletionsInstalled "${sandbox}/stage/opt/purge"
}

# A relative prefix would be relative to the directory of the justfile, since
# just runs recipes there.
function TestInstallRejectsRelativePrefix()
{
    RunJust install-completions --prefix=relative
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: expected an absolute prefix, got 'relative'"
    ExpectNotInstalled "${ROOT_DIR}/relative"
}

function TestInstallScriptRequiresPrefix()
{
    RunInstallScript bash
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: expected --prefix"
}

function TestInstallScriptRejectsUnknownComponent()
{
    RunInstallScript --prefix="${sandbox}/prefix" bash tcsh
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: unknown component 'tcsh'"
    ExpectNotInstalled "${sandbox}/prefix"
}

function TestInstallCompletionsInstallsOnlyCompletions()
{
    RunJust install-completions --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectCompletionsInstalled "${sandbox}/prefix"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_SCRIPT}"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_MAN_PAGE}"
}

function TestInstallBashCompletionInstallsOnlyIt()
{
    RunJust install-bash-completion --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectInstalledFile "${sandbox}/prefix/${INSTALLED_COMPLETION}" 644 "${COMPLETION}"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_ZSH_COMPLETION}"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_FISH_COMPLETION}"
}

function TestInstallZshCompletionInstallsOnlyIt()
{
    RunJust install-zsh-completion --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectInstalledFile "${sandbox}/prefix/${INSTALLED_ZSH_COMPLETION}" 644 "${ZSH_COMPLETION}"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_COMPLETION}"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_FISH_COMPLETION}"
}

function TestInstallFishCompletionInstallsOnlyIt()
{
    RunJust install-fish-completion --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectInstalledFile "${sandbox}/prefix/${INSTALLED_FISH_COMPLETION}" 644 "${FISH_COMPLETION}"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_COMPLETION}"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_ZSH_COMPLETION}"
}

function ExpectNothingInstalled()
{
    local prefix="$1"

    ExpectNotInstalled "${prefix}/${INSTALLED_SCRIPT}"
    ExpectNotInstalled "${prefix}/${INSTALLED_MAN_PAGE}"
    ExpectNotInstalled "${prefix}/${INSTALLED_COMPLETION}"
    ExpectNotInstalled "${prefix}/${INSTALLED_ZSH_COMPLETION}"
    ExpectNotInstalled "${prefix}/${INSTALLED_FISH_COMPLETION}"
}

function TestUninstallRemovesInstalledFiles()
{
    RunJust install --prefix="${sandbox}/prefix"
    RunJust uninstall --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectNothingInstalled "${sandbox}/prefix"
}

# The directories may hold files of other packages, such as the completions of
# other commands.
function TestUninstallKeepsOtherFiles()
{
    local other_completion="${sandbox}/prefix/${INSTALLED_ZSH_COMPLETION%/*}/_other"

    RunJust install --prefix="${sandbox}/prefix"
    touch "${other_completion}"
    RunJust uninstall --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectNothingInstalled "${sandbox}/prefix"

    if [[ ! -f ${other_completion} ]]; then
        Fail "expected '${other_completion}' to remain"
    fi
}

function TestUninstallSucceedsWithoutInstalledFiles()
{
    mkdir "${sandbox}/prefix"
    RunJust uninstall --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectNothingInstalled "${sandbox}/prefix"
}

function TestUninstallDefaultsToLocalOfHomeWithoutRoot()
{
    FakeUserId 1000
    RunJust install
    RunJust uninstall
    ExpectStatus 0
    ExpectNothingInstalled "${sandbox}/home/.local"
}

# DESTDIR keeps the default prefix of root from pointing to the real one.
function TestUninstallDefaultsToUsrLocalWithRoot()
{
    FakeUserId 0
    DESTDIR="${sandbox}/stage" RunJust install
    DESTDIR="${sandbox}/stage" RunJust uninstall
    ExpectStatus 0
    ExpectNothingInstalled "${sandbox}/stage/usr/local"
}

function TestUninstallCompletionsRemovesOnlyCompletions()
{
    RunJust install --prefix="${sandbox}/prefix"
    RunJust uninstall-completions --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectScriptAndManPageInstalled "${sandbox}/prefix"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_COMPLETION}"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_ZSH_COMPLETION}"
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_FISH_COMPLETION}"
}

function TestUninstallBashCompletionRemovesOnlyIt()
{
    RunJust install-completions --prefix="${sandbox}/prefix"
    RunJust uninstall-bash-completion --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_COMPLETION}"
    ExpectInstalledFile "${sandbox}/prefix/${INSTALLED_ZSH_COMPLETION}" 644 "${ZSH_COMPLETION}"
    ExpectInstalledFile "${sandbox}/prefix/${INSTALLED_FISH_COMPLETION}" 644 "${FISH_COMPLETION}"
}

function TestUninstallZshCompletionRemovesOnlyIt()
{
    RunJust install-completions --prefix="${sandbox}/prefix"
    RunJust uninstall-zsh-completion --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_ZSH_COMPLETION}"
    ExpectInstalledFile "${sandbox}/prefix/${INSTALLED_COMPLETION}" 644 "${COMPLETION}"
    ExpectInstalledFile "${sandbox}/prefix/${INSTALLED_FISH_COMPLETION}" 644 "${FISH_COMPLETION}"
}

function TestUninstallFishCompletionRemovesOnlyIt()
{
    RunJust install-completions --prefix="${sandbox}/prefix"
    RunJust uninstall-fish-completion --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectNotInstalled "${sandbox}/prefix/${INSTALLED_FISH_COMPLETION}"
    ExpectInstalledFile "${sandbox}/prefix/${INSTALLED_COMPLETION}" 644 "${COMPLETION}"
    ExpectInstalledFile "${sandbox}/prefix/${INSTALLED_ZSH_COMPLETION}" 644 "${ZSH_COMPLETION}"
}

readonly PACKAGE_VERSION=1.2.3
readonly DEB="git-purge-branches_${PACKAGE_VERSION}_all.deb"
readonly TARBALL="git-purge-branches-${PACKAGE_VERSION}.tar.gz"
# The modes, owners and paths of the files of the Debian package. Debian
# searches zsh completions of packages in vendor-completions, and its policy
# requires compressed manual pages and a copyright file.
readonly DEB_FILES="-rwxr-xr-x root/root ./usr/bin/git-purge-branches
-rw-r--r-- root/root ./usr/share/bash-completion/completions/git-purge-branches
-rw-r--r-- root/root ./usr/share/doc/git-purge-branches/changelog.gz
-rw-r--r-- root/root ./usr/share/doc/git-purge-branches/copyright
-rw-r--r-- root/root ./usr/share/fish/vendor_completions.d/git-purge-branches.fish
-rw-r--r-- root/root ./usr/share/man/man1/git-purge-branches.1.gz
-rw-r--r-- root/root ./usr/share/zsh/vendor-completions/_git-purge-branches"

function ExpectLines()
{
    local actual="$1"
    local expected="$2"

    if [[ ${actual} != "${expected}" ]]; then
        Fail "expected"$'\n'"${expected}"$'\n'"    got"$'\n'"${actual}"
    fi
}

# Compares the files of a verbose listing of dpkg-deb or tar in the given file,
# as lines of their mode, owner and path sorted by path, with the expected ones.
function ExpectArchiveFiles()
{
    local listing="$1"
    local expected="$2"
    local actual

    awk '$1 !~ /^d/ { print $1, $2, $6 }' "${listing}" >"${sandbox}/files"
    actual="$(LC_ALL=C sort -k 3 "${sandbox}/files")"
    ExpectLines "${actual}" "${expected}"
}

function ExpectSameContents()
{
    local actual="$1"
    local expected="$2"

    if ! cmp --quiet "${actual}" "${expected}"; then
        Fail "expected '${actual}' to equal '${expected}'"
    fi
}

function TestDebHasControlFields()
{
    local fields

    RequireCommands dpkg-buildpackage dh || return

    RunJust deb --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
    ExpectStatus 0
    fields="$(dpkg-deb --field "${sandbox}/dist/${DEB}" Package Version Architecture Maintainer Depends)"
    ExpectLines "${fields}" "Package: git-purge-branches
Version: ${PACKAGE_VERSION}
Architecture: all
Maintainer: Sergiu Deitsch <sergiu.deitsch@gmail.com>
Depends: git (>= 1:2.41)"
}

function TestDebInstallsFilesBelowUsr()
{
    RequireCommands dpkg-buildpackage dh || return

    RunJust deb --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
    ExpectStatus 0
    dpkg-deb --contents "${sandbox}/dist/${DEB}" >"${sandbox}/listing"
    ExpectArchiveFiles "${sandbox}/listing" "${DEB_FILES}"
}

# Files that the build writes instead of installing get the modes of the
# others even if the umask removes the permissions of the group and others.
function TestDebHasModesUnderRestrictiveUmask()
{
    RequireCommands dpkg-buildpackage dh || return

    (
        umask 077 && RunJust deb --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
        echo "${status}" >"${sandbox}/status"
    )
    status="$(<"${sandbox}/status")"
    ExpectStatus 0
    dpkg-deb --contents "${sandbox}/dist/${DEB}" >"${sandbox}/listing"
    ExpectArchiveFiles "${sandbox}/listing" "${DEB_FILES}"
    dpkg-deb --ctrl-tarfile "${sandbox}/dist/${DEB}" >"${sandbox}/control.tar"
    tar --list --verbose --file="${sandbox}/control.tar" >"${sandbox}/listing"
    ExpectArchiveFiles "${sandbox}/listing" "-rw-r--r-- root/root ./control
-rw-r--r-- root/root ./md5sums"
}

# The changelog names the release, and the maintainer signs it.
function TestDebHasChangelogOfRelease()
{
    local root="${sandbox}/root"
    local changelog

    RequireCommands dpkg-buildpackage dh || return

    RunJust deb --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
    ExpectStatus 0
    dpkg-deb --extract "${sandbox}/dist/${DEB}" "${root}"
    gzip --decompress --stdout "${root}/usr/share/doc/git-purge-branches/changelog.gz" \
        >"${sandbox}/changelog"
    # The date of the signature is that of the last commit.
    changelog="$(sed 's/^\( -- .*>\)  .*$/\1/' "${sandbox}/changelog")"
    ExpectLines "${changelog}" "git-purge-branches (${PACKAGE_VERSION}) unstable; urgency=medium

  * Release ${PACKAGE_VERSION}.

 -- Sergiu Deitsch <sergiu.deitsch@gmail.com>"
}

function TestDebContainsSources()
{
    local root="${sandbox}/root"

    RequireCommands dpkg-buildpackage dh || return

    RunJust deb --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
    ExpectStatus 0
    dpkg-deb --extract "${sandbox}/dist/${DEB}" "${root}"
    gzip --decompress --keep "${root}/usr/share/man/man1/git-purge-branches.1.gz"

    ExpectSameContents "${root}/usr/bin/git-purge-branches" "${SCRIPT}"
    ExpectSameContents "${root}/usr/share/man/man1/git-purge-branches.1" "${MAN_PAGE}"
    ExpectSameContents "${root}/usr/share/bash-completion/completions/git-purge-branches" "${COMPLETION}"
    ExpectSameContents "${root}/usr/share/zsh/vendor-completions/_git-purge-branches" "${ZSH_COMPLETION}"
    ExpectSameContents "${root}/usr/share/fish/vendor_completions.d/git-purge-branches.fish" "${FISH_COMPLETION}"
}

function TestTarballHasInstallLayout()
{
    local top="git-purge-branches-${PACKAGE_VERSION}"

    RunJust tarball --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
    ExpectStatus 0
    tar --list --verbose --gzip --file="${sandbox}/dist/${TARBALL}" >"${sandbox}/listing"
    ExpectArchiveFiles "${sandbox}/listing" \
        "-rwxr-xr-x root/root ${top}/${INSTALLED_SCRIPT}
-rw-r--r-- root/root ${top}/${INSTALLED_COMPLETION}
-rw-r--r-- root/root ${top}/share/doc/git-purge-branches/GPL-3.0-or-later.txt
-rw-r--r-- root/root ${top}/${INSTALLED_FISH_COMPLETION}
-rw-r--r-- root/root ${top}/${INSTALLED_MAN_PAGE}
-rw-r--r-- root/root ${top}/${INSTALLED_ZSH_COMPLETION}"
}

function TestTarballContainsSources()
{
    local top="${sandbox}/git-purge-branches-${PACKAGE_VERSION}"

    RunJust tarball --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
    ExpectStatus 0
    tar --extract --gzip --file="${sandbox}/dist/${TARBALL}" --directory="${sandbox}"

    ExpectSameContents "${top}/${INSTALLED_SCRIPT}" "${SCRIPT}"
    ExpectSameContents "${top}/${INSTALLED_MAN_PAGE}" "${MAN_PAGE}"
    ExpectSameContents "${top}/${INSTALLED_COMPLETION}" "${COMPLETION}"
    ExpectSameContents "${top}/${INSTALLED_ZSH_COMPLETION}" "${ZSH_COMPLETION}"
    ExpectSameContents "${top}/${INSTALLED_FISH_COMPLETION}" "${FISH_COMPLETION}"
    ExpectSameContents "${top}/share/doc/git-purge-branches/GPL-3.0-or-later.txt" \
        "${ROOT_DIR}/LICENSES/GPL-3.0-or-later.txt"
}

# Release tags such as v1.2.3 carry a prefix that Debian versions lack.
function TestPackagesRejectVersionWithoutLeadingDigit()
{
    RunJust deb --version=v1.2.3 --output="${sandbox}/dist"
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: expected a version that starts with a digit, got 'v1.2.3'"
    ExpectNotInstalled "${sandbox}/dist"
}

function TestPackagesRejectVersionWithHyphen()
{
    RunJust tarball --version=1.2-3 --output="${sandbox}/dist"
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: expected a version without a hyphen, got '1.2-3'"
    ExpectNotInstalled "${sandbox}/dist"
}

function TestPackageScriptRejectsUnknownFormat()
{
    timeout "${HANG_TIMEOUT}" "${ROOT_DIR}/scripts/package.sh" --version="${PACKAGE_VERSION}" \
        --output="${sandbox}/dist" deb rpm >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: unknown format 'rpm'"
    ExpectNotInstalled "${sandbox}/dist"
}

readonly PACMAN="git-purge-branches-${PACKAGE_VERSION}-1-any.pkg.tar.zst"

# Skips the running test and returns 1 unless makepkg exists and may run,
# which it refuses for root.
function RequireMakepkg()
{
    RequireCommands makepkg || return

    if ((EUID == 0)); then
        Skip "skipped since makepkg refuses to run as root"
        return 1
    fi
}

# Creates a git repository in the sandbox with the files of the checkout,
# including uncommitted ones, in a single commit, so that the tests control its
# tags.
function CreateCheckoutRepository()
{
    local checkout="${sandbox}/checkout"

    git -C "${ROOT_DIR}" ls-files -z --cached --others --exclude-standard >"${sandbox}/files"
    tar --create --file="${sandbox}/checkout.tar" --directory="${ROOT_DIR}" --null \
        --files-from="${sandbox}/files"
    mkdir "${checkout}"
    tar --extract --file="${sandbox}/checkout.tar" --directory="${checkout}"
    git -C "${checkout}" init -q -b master
    git -C "${checkout}" add --all
    git -C "${checkout}" commit -q -m checkout
}

# Extracts the archive that git archive creates of the repository of
# CreateCheckoutRepository, as a release on GitHub offers it, into the sandbox.
function CreateSourceArchive()
{
    git -C "${sandbox}/checkout" archive --output="${sandbox}/archive.tar" HEAD
    mkdir "${sandbox}/archive"
    tar --extract --file="${sandbox}/archive.tar" --directory="${sandbox}/archive"
}

# Runs scripts/version.sh of the sources in the given directory with the
# remaining arguments and stores its exit status.
function RunVersionIn()
{
    local directory="$1"
    shift

    timeout "${HANG_TIMEOUT}" "${directory}/scripts/version.sh" "$@" \
        >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
}

function TestVersionOfTaggedCommit()
{
    CreateCheckoutRepository
    git -C "${sandbox}/checkout" tag "v${PACKAGE_VERSION}"
    RunVersionIn "${sandbox}/checkout" version
    ExpectStatus 0
    ExpectStdout "${PACKAGE_VERSION}"
}

function TestVersionOfCommitAfterTag()
{
    local hash

    CreateCheckoutRepository
    git -C "${sandbox}/checkout" tag "v${PACKAGE_VERSION}"
    git -C "${sandbox}/checkout" commit -q --allow-empty -m next
    hash="$(git -C "${sandbox}/checkout" rev-parse --short HEAD)"
    RunVersionIn "${sandbox}/checkout" version
    ExpectStatus 0
    ExpectStdout "${PACKAGE_VERSION}.r1.${hash}"
}

# Debian requires versions to start with a digit.
function TestVersionWithoutTag()
{
    local hash

    CreateCheckoutRepository
    git -C "${sandbox}/checkout" commit -q --allow-empty -m next
    hash="$(git -C "${sandbox}/checkout" rev-parse --short HEAD)"
    RunVersionIn "${sandbox}/checkout" version
    ExpectStatus 0
    ExpectStdout "0.r2.${hash}"
}

function TestVersionOfArchive()
{
    CreateCheckoutRepository
    git -C "${sandbox}/checkout" tag "v${PACKAGE_VERSION}"
    CreateSourceArchive
    RunVersionIn "${sandbox}/archive" version
    ExpectStatus 0
    ExpectStdout "${PACKAGE_VERSION}"
}

function TestVersionOfArchiveWithoutTag()
{
    CreateCheckoutRepository
    CreateSourceArchive
    RunVersionIn "${sandbox}/archive" version
    ExpectStatus 1
    ExpectStderrContains "error: expected a tag that describes the archived commit, got none"
}

function TestDateOfCheckoutAndArchive()
{
    local date

    CreateCheckoutRepository
    git -C "${sandbox}/checkout" tag "v${PACKAGE_VERSION}"
    date="$(git -C "${sandbox}/checkout" log -1 --format=%ct)"
    CreateSourceArchive
    RunVersionIn "${sandbox}/checkout" date
    ExpectStatus 0
    ExpectStdout "${date}"
    RunVersionIn "${sandbox}/archive" date
    ExpectStatus 0
    ExpectStdout "${date}"
}

# Runs makepkg for the PKGBUILD of the sources in the given directory, as a
# user would, with its outputs in the sandbox. The dependencies are not
# checked, since systems other than Arch lack the database of pacman. The
# extension of the package follows the configuration of makepkg.
function RunMakepkgIn()
{
    local directory="$1"

    (cd "${directory}" && PKGDEST="${sandbox}/packages" BUILDDIR="${sandbox}/build" \
        SRCDEST="${sandbox}/sources" timeout "${HANG_TIMEOUT}" makepkg --nodeps -D pacman) \
        >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
}

function TestMakepkgBuildsTaggedCheckout()
{
    RequireMakepkg || return

    CreateCheckoutRepository
    git -C "${sandbox}/checkout" tag "v${PACKAGE_VERSION}"
    RunMakepkgIn "${sandbox}/checkout"
    ExpectStatus 0
    ExpectExists "${sandbox}/packages/${PACMAN%.tar.zst}.tar."*
}

function TestMakepkgBuildsArchive()
{
    RequireMakepkg || return

    CreateCheckoutRepository
    git -C "${sandbox}/checkout" tag "v${PACKAGE_VERSION}"
    CreateSourceArchive
    RunMakepkgIn "${sandbox}/archive"
    ExpectStatus 0
    ExpectExists "${sandbox}/packages/${PACMAN%.tar.zst}.tar."*
}

function TestPackagesDefaultToVersionOfSources()
{
    CreateCheckoutRepository
    git -C "${sandbox}/checkout" tag "v${PACKAGE_VERSION}"
    RunJustIn "${sandbox}/checkout" tarball --output="${sandbox}/dist"
    ExpectStatus 0
    ExpectExists "${sandbox}/dist/${TARBALL}"
}

# An archive of the sources, such as one that GitHub offers for a release, has
# no repository of git.
function TestPackagesBuildFromArchive()
{
    RequireCommands dpkg-buildpackage dh || return

    CreateCheckoutRepository
    git -C "${sandbox}/checkout" tag "v${PACKAGE_VERSION}"
    CreateSourceArchive
    RunJustIn "${sandbox}/archive" tarball --output="${sandbox}/dist"
    ExpectStatus 0
    ExpectExists "${sandbox}/dist/${TARBALL}"
    RunJustIn "${sandbox}/archive" deb --output="${sandbox}/dist"
    ExpectStatus 0
    ExpectExists "${sandbox}/dist/${DEB}"
}

# The build date is that of the last commit.
function TestPacmanHasPackageInfo()
{
    local fields
    local date

    RequireMakepkg || return

    date="$(git -C "${ROOT_DIR}" log -1 --format=%ct)"
    RunJust pacman --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
    ExpectStatus 0
    tar --extract --to-stdout --file="${sandbox}/dist/${PACMAN}" .PKGINFO >"${sandbox}/info"
    fields="$(grep -E '^(pkgname|pkgver|builddate|packager|arch|depend) = ' "${sandbox}/info")"
    ExpectLines "${fields}" "pkgname = git-purge-branches
pkgver = ${PACKAGE_VERSION}-1
builddate = ${date}
packager = Sergiu Deitsch <sergiu.deitsch@gmail.com>
arch = any
depend = bash
depend = git>=2.41"
}

# makepkg compresses the manual pages.
function TestPacmanInstallsFilesBelowUsr()
{
    RequireMakepkg || return

    RunJust pacman --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
    ExpectStatus 0
    tar --list --verbose --file="${sandbox}/dist/${PACMAN}" >"${sandbox}/listing"
    # The metadata of pacman, such as .PKGINFO, is no installed file.
    sed --in-place '/ \.[A-Z]*$/d' "${sandbox}/listing"
    ExpectArchiveFiles "${sandbox}/listing" \
        "-rwxr-xr-x root/root usr/bin/git-purge-branches
-rw-r--r-- root/root usr/share/bash-completion/completions/git-purge-branches
-rw-r--r-- root/root usr/share/fish/vendor_completions.d/git-purge-branches.fish
-rw-r--r-- root/root usr/share/man/man1/git-purge-branches.1.gz
-rw-r--r-- root/root usr/share/zsh/site-functions/_git-purge-branches"
}

function TestPacmanContainsSources()
{
    local root="${sandbox}/root"

    RequireMakepkg || return

    RunJust pacman --version="${PACKAGE_VERSION}" --output="${sandbox}/dist"
    ExpectStatus 0
    mkdir "${root}"
    tar --extract --file="${sandbox}/dist/${PACMAN}" --directory="${root}"
    gzip --decompress --keep "${root}/usr/share/man/man1/git-purge-branches.1.gz"

    ExpectSameContents "${root}/usr/bin/git-purge-branches" "${SCRIPT}"
    ExpectSameContents "${root}/usr/share/man/man1/git-purge-branches.1" "${MAN_PAGE}"
    ExpectSameContents "${root}/usr/share/bash-completion/completions/git-purge-branches" "${COMPLETION}"
    ExpectSameContents "${root}/usr/share/zsh/site-functions/_git-purge-branches" "${ZSH_COMPLETION}"
    ExpectSameContents "${root}/usr/share/fish/vendor_completions.d/git-purge-branches.fish" "${FISH_COMPLETION}"
}

readonly RELEASE_SERVER="${ROOT_DIR}/tests/release-server.py"

# Serves a release of the version of the packages in the sandbox as GitHub
# serves release assets, with the given tag as the latest release, and stores
# the URL of its releases in releases.
function StartReleaseServer()
{
    local latest_tag="$1"
    local assets="${sandbox}/server/releases/download/v${PACKAGE_VERSION}"
    local -i waited=0

    RunJust tarball --version="${PACKAGE_VERSION}" --output="${assets}"
    (cd "${assets}" && sha256sum "${TARBALL}" >SHA256SUMS)

    python3 "${RELEASE_SERVER}" "${sandbox}/server" "${latest_tag}" "${sandbox}/port" &
    server_pid=$!

    # The server writes the port once it accepts connections.
    until [[ -s ${sandbox}/port ]]; do
        if ((++waited > HANG_TIMEOUT * 10)); then
            Fail "expected the release server to start within ${HANG_TIMEOUT} s"
            return 1
        fi
        sleep 0.1
    done

    releases="http://127.0.0.1:$(<"${sandbox}/port")/releases"
}

# Runs install.sh from standard input with the given arguments, as
# curl ... | bash -s -- <arguments> does, against the release server, and
# stores its exit status.
function RunGet()
{
    (cd "${sandbox}" && HOME="${sandbox}/home" PATH="${sandbox}/fake-bin:${PATH}" \
        GIT_PURGE_BRANCHES_RELEASES="${releases}" \
        timeout "${HANG_TIMEOUT}" bash -s -- "$@" <"${ROOT_DIR}/install.sh") \
        >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
}

function TestGetInstallsLatestRelease()
{
    StartReleaseServer "v${PACKAGE_VERSION}" || return
    FakeUserId 1000
    RunGet
    ExpectStatus 0
    ExpectScriptAndManPageInstalled "${sandbox}/home/.local"
    ExpectCompletionsInstalled "${sandbox}/home/.local"
}

# The latest release differs from the requested one, which the server has.
function TestGetInstallsGivenVersionBelowPrefix()
{
    StartReleaseServer v9.9.9 || return
    RunGet --version="${PACKAGE_VERSION}" --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectScriptAndManPageInstalled "${sandbox}/prefix"
    ExpectCompletionsInstalled "${sandbox}/prefix"
}

# A user other than root cannot write to /usr/local, which the error names.
function TestGetDefaultsToUsrLocalWithRoot()
{
    if ((EUID == 0)); then
        Skip "skipped since root may write to /usr/local"
        return
    fi

    StartReleaseServer "v${PACKAGE_VERSION}" || return
    FakeUserId 0
    RunGet
    ExpectStatus 1
    ExpectStderrContains "error: failed to install git-purge-branches ${PACKAGE_VERSION} below '/usr/local'"
}

function TestGetRejectsTamperedTarball()
{
    local assets="${sandbox}/server/releases/download/v${PACKAGE_VERSION}"

    StartReleaseServer "v${PACKAGE_VERSION}" || return
    echo tampered >>"${assets}/${TARBALL}"
    RunGet --prefix="${sandbox}/prefix"
    ExpectStatus 1
    ExpectStderrContains "error: expected the checksum of ${TARBALL} in SHA256SUMS"
    ExpectNotInstalled "${sandbox}/prefix"
}

function TestGetRejectsTarballWithoutChecksum()
{
    local assets="${sandbox}/server/releases/download/v${PACKAGE_VERSION}"

    StartReleaseServer "v${PACKAGE_VERSION}" || return
    : >"${assets}/SHA256SUMS"
    RunGet --prefix="${sandbox}/prefix"
    ExpectStatus 1
    ExpectStderrContains "error: expected the checksum of ${TARBALL} in SHA256SUMS"
    ExpectNotInstalled "${sandbox}/prefix"
}

# GitHub redirects the latest release to the list of releases if all of them
# are prereleases.
function TestGetReportsMissingLatestRelease()
{
    StartReleaseServer "" || return
    RunGet --prefix="${sandbox}/prefix"
    ExpectStatus 1
    ExpectStderrContains "error: found no release that is not a prerelease at ${releases}, which --version selects"
    ExpectNotInstalled "${sandbox}/prefix"
}

function TestGetReportsMissingRelease()
{
    StartReleaseServer "v${PACKAGE_VERSION}" || return
    RunGet --version=9.9.9 --prefix="${sandbox}/prefix"
    ExpectStatus 1
    ExpectStderrContains "error: failed to download git-purge-branches-9.9.9.tar.gz"
    ExpectNotInstalled "${sandbox}/prefix"
}

# The directories may hold files of other packages, such as the completions of
# other commands.
function TestGetUninstallsRelease()
{
    local other_completion="${sandbox}/prefix/${INSTALLED_ZSH_COMPLETION%/*}/_other"

    StartReleaseServer "v${PACKAGE_VERSION}" || return
    RunGet --prefix="${sandbox}/prefix"
    touch "${other_completion}"
    RunGet --prefix="${sandbox}/prefix" --uninstall
    ExpectStatus 0
    ExpectNothingInstalled "${sandbox}/prefix"
    ExpectNotInstalled "${sandbox}/prefix/share/doc/git-purge-branches/GPL-3.0-or-later.txt"
    ExpectExists "${other_completion}"
}

# macOS extracts with the tar of libarchive, which bsdtar provides elsewhere.
function TestGetInstallsWithBsdtar()
{
    local bsdtar

    RequireCommands bsdtar || return

    bsdtar="$(command -v bsdtar)"
    StartReleaseServer "v${PACKAGE_VERSION}" || return
    mkdir -p "${sandbox}/fake-bin"
    ln -s "${bsdtar}" "${sandbox}/fake-bin/tar"
    RunGet --prefix="${sandbox}/prefix"
    ExpectStatus 0
    ExpectScriptAndManPageInstalled "${sandbox}/prefix"
    ExpectCompletionsInstalled "${sandbox}/prefix"
    RunGet --prefix="${sandbox}/prefix" --uninstall
    ExpectStatus 0
    ExpectNothingInstalled "${sandbox}/prefix"
}

function TestGetRejectsRelativePrefix()
{
    StartReleaseServer "v${PACKAGE_VERSION}" || return
    RunGet --prefix=relative
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: expected an absolute prefix, got 'relative'"
    ExpectNotInstalled "${sandbox}/relative"
}

# GitHub Pages serves the manual page of the command as the page of the site.
function TestPagesRenderManualPage()
{
    local page="${sandbox}/site/index.html"

    RunJust pages --output="${sandbox}/site"
    ExpectStatus 0
    ExpectExists "${page}"
    # The title, the synopsis and the last section show the whole manual.
    grep -q '<title>git-purge-branches(1)</title>' "${page}" || Fail "expected the title of the manual in '${page}'"
    grep -qF 'git purge-branches</strong> [<a href="#option-dry-run"><strong>-n</strong></a>' "${page}" || Fail "expected the synopsis in '${page}'"
    grep -q '>See also<' "${page}" || Fail "expected the last section in '${page}'"
}

# Expects the HTML page of the manual in the sandbox to contain the given
# markup.
function ExpectPageContains()
{
    local markup="$1"
    local page="${sandbox}/site/index.html"

    if ! grep -qF -- "${markup}" "${page}"; then
        Fail "expected '${markup}' in '${page}'"
    fi
}

# Expects the manual page to contain the given troff markup.
function ExpectManPageContains()
{
    local markup="$1"

    if ! grep -qF -- "${markup}" "${MAN_PAGE}"; then
        Fail "expected '${markup}' in '${MAN_PAGE}'"
    fi
}

# The HTML page sets commands, options and other literal input, which the
# manual marks in bold, in a monospace font, as the documentation of Git does.
function TestPagesSetLiteralInputInMonospace()
{
    RunJust pages --output="${sandbox}/site"
    ExpectStatus 0
    ExpectPageContains '#content strong { font-family: "Droid Sans Mono", "DejaVu Sans Mono", monospace; }'
}

# The HTML page highlights the shell sessions of the examples, such as their
# options.
function TestPagesHighlightExamples()
{
    RunJust pages --output="${sandbox}/site"
    ExpectStatus 0
    ExpectPageContains '<code data-lang="console">'
    ExpectPageContains 'git purge-branches <span class="nt">--dry-run</span>'
}

# The HTML page follows the color scheme of the browser, from the text and the
# highlighted examples to the corner that links to the project.
function TestPagesFollowDarkColorScheme()
{
    RunJust pages --output="${sandbox}/site"
    ExpectStatus 0
    ExpectPageContains '@media (prefers-color-scheme: dark)'
    ExpectPageContains 'color-scheme: light dark;'
    ExpectPageContains '.github-corner svg { fill: #f0f6fc !important; color: #0d1117 !important; }'
    ExpectPageContains '#header > h1:first-child { color: #e6edf3; }'
    ExpectPageContains 'pre.rouge .nt {'
}

# The HTML page names the version of its sources, so that the switcher of
# versions of the published site selects it.
function TestPagesNameVersion()
{
    local version

    version="$("${ROOT_DIR}/scripts/version.sh" version)"
    RunJust pages --output="${sandbox}/site"
    ExpectStatus 0
    ExpectPageContains "<meta name=\"manual-version\" content=\"${version}\">"
    ExpectPageContains "Version ${version}"
    ExpectPageContains "fetch(root + 'versions.json')"
}

# The HTML page links back to the project on GitHub from its corner.
function TestPagesLinkToProject()
{
    RunJust pages --output="${sandbox}/site"
    ExpectStatus 0
    ExpectPageContains '<a href="https://github.com/sergiud/git-purge-branches" class="github-corner" aria-label="View source on GitHub">'
    ExpectPageContains 'class="octo-arm"'
}

# The site serves the install script of the release under a short address.
function TestPagesServeInstallScript()
{
    RunJust pages --output="${sandbox}/site"
    ExpectStatus 0
    ExpectExists "${sandbox}/site/install.sh"
    ExpectSameContents "${sandbox}/site/install.sh" "${ROOT_DIR}/install.sh"
}

# The HTML page links the commands of Git to their documentation, both in the
# text and as related commands.
function TestPagesLinkGitCommandsToGitDocumentation()
{
    local docs=https://git-scm.com/docs
    local command

    RunJust pages --output="${sandbox}/site"
    ExpectStatus 0

    for command in git-branch git-cherry git-for-each-ref; do
        ExpectPageContains "<a href=\"${docs}/${command}\"><strong>${command}</strong>(1)</a>"
    done

    ExpectPageContains "<a href=\"${docs}/git-branch\"><strong>git branch -d</strong></a>"
    ExpectPageContains "<a href=\"${docs}/git-branch\"><strong>git branch --delete-merged</strong></a>"
    ExpectPageContains "<a href=\"${docs}/git-cherry\"><strong>git cherry</strong></a>"
}

# Every section, option and setting of the HTML page has an anchor, and the
# text links the options, the setting and the sections it mentions to them.
function TestPagesLinkOptionsAndSections()
{
    local anchor

    RunJust pages --output="${sandbox}/site"
    ExpectStatus 0

    # The manual page doctype renders the section Name as part of the header.
    for anchor in synopsis description options exit-status configuration examples comparison see-also; do
        ExpectPageContains "<h2 id=\"${anchor}\"><a class=\"anchor\" href=\"#${anchor}\"></a>"
    done

    # The options, the argument and the setting show a link to their anchor on
    # hover, as the sections do.
    for anchor in option-dry-run option-equivalent option-interactive option-help argument-commit setting-keep setting-delete-merged; do
        ExpectPageContains "<dt class=\"hdlist1\"><a id=\"${anchor}\"></a><a class=\"anchor\" href=\"#${anchor}\"></a>"
    done

    ExpectPageContains 'dt.hdlist1:hover > a.anchor'

    ExpectPageContains '<a href="#option-dry-run"><strong>--dry-run</strong></a>'
    ExpectPageContains '<a href="#option-equivalent"><strong>--equivalent</strong></a>'
    ExpectPageContains '<a href="#setting-delete-merged"><strong>branch.&lt;name&gt;.deleteMerged</strong></a>'
    ExpectPageContains '<a href="#configuration">CONFIGURATION</a>'
    ExpectPageContains '<a href="#description">described above</a>'
}

# The terminal shows the commands, options and sections by name, without
# addresses.
function TestManPageNamesReferencesWithoutLinks()
{
    RunJust man
    ExpectStatus 0

    ExpectManPageContains '\fBgit\-branch\fP(1), \fBgit\-cherry\fP(1), \fBgit\-for\-each\-ref\fP(1)'
    ExpectManPageContains 'with \fBgit branch \-d\fP, which refuses'
    ExpectManPageContains 'that \fB\-\-equivalent\fP selects'
    ExpectManPageContains 'as described under CONFIGURATION.'

    if grep -qE 'git-scm\.com|#(option|setting|configuration|description)' "${MAN_PAGE}"; then
        Fail "expected no addresses in '${MAN_PAGE}'"
    fi
}

# Creates the site of the given release in the sandbox, as just pages renders
# it, with files that name the release.
function CreateReleaseSite()
{
    local version="$1"
    local site="${sandbox}/site-${version}"

    mkdir -p "${site}"
    echo "manual ${version}" >"${site}/index.html"
    echo "install ${version}" >"${site}/install.sh"
}

# Runs scripts/publish-pages.sh with the given arguments and stores its exit
# status.
function RunPublishPages()
{
    timeout "${HANG_TIMEOUT}" "${ROOT_DIR}/scripts/publish-pages.sh" "$@" \
        >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
}

# Publishes the site of the given release, which CreateReleaseSite created, to
# the published site in the sandbox.
function PublishRelease()
{
    local version="$1"

    RunPublishPages --version="${version}" "${sandbox}/site-${version}" "${sandbox}/published"
}

function ExpectFileContent()
{
    local path="$1"
    local expected="$2"
    local actual

    if [[ ! -f ${path} ]]; then
        Fail "expected file '${path}'"
        return
    fi

    actual="$(<"${path}")"

    if [[ ${actual} != "${expected}" ]]; then
        Fail "expected '${expected}' in '${path}', got '${actual}'"
    fi
}

function TestPublishPagesAddsFirstRelease()
{
    CreateReleaseSite 1.2.3
    PublishRelease 1.2.3
    ExpectStatus 0
    ExpectFileContent "${sandbox}/published/1.2.3/index.html" "manual 1.2.3"
    ExpectFileContent "${sandbox}/published/index.html" "manual 1.2.3"
    ExpectFileContent "${sandbox}/published/install.sh" "install 1.2.3"
    ExpectFileContent "${sandbox}/published/versions.json" '["1.2.3"]'
}

# The root serves the release published last, while the earlier ones stay
# below their versions.
function TestPublishPagesKeepsEarlierReleases()
{
    CreateReleaseSite 1.2.3
    CreateReleaseSite 1.3.0
    CreateReleaseSite 1.4.0
    PublishRelease 1.2.3
    PublishRelease 1.3.0
    PublishRelease 1.4.0
    ExpectStatus 0
    ExpectFileContent "${sandbox}/published/1.2.3/index.html" "manual 1.2.3"
    ExpectFileContent "${sandbox}/published/1.3.0/index.html" "manual 1.3.0"
    ExpectFileContent "${sandbox}/published/index.html" "manual 1.4.0"
    ExpectFileContent "${sandbox}/published/install.sh" "install 1.4.0"
    ExpectFileContent "${sandbox}/published/versions.json" '["1.4.0","1.3.0","1.2.3"]'
}

# Publishing a release again replaces its site and moves it to the front.
function TestPublishPagesRepublishesRelease()
{
    CreateReleaseSite 1.2.3
    CreateReleaseSite 1.3.0
    PublishRelease 1.2.3
    PublishRelease 1.3.0
    echo "manual 1.2.3 fixed" >"${sandbox}/site-1.2.3/index.html"
    PublishRelease 1.2.3
    ExpectStatus 0
    ExpectFileContent "${sandbox}/published/1.2.3/index.html" "manual 1.2.3 fixed"
    ExpectFileContent "${sandbox}/published/1.3.0/index.html" "manual 1.3.0"
    ExpectFileContent "${sandbox}/published/versions.json" '["1.2.3","1.3.0"]'
}

# The published site may hold files of its own, such as the marker that turns
# off Jekyll.
function TestPublishPagesKeepsOtherFiles()
{
    mkdir -p "${sandbox}/published"
    touch "${sandbox}/published/.nojekyll"
    CreateReleaseSite 1.2.3
    PublishRelease 1.2.3
    ExpectStatus 0
    ExpectExists "${sandbox}/published/.nojekyll"
}

function TestPublishPagesRejectsInvalidVersion()
{
    local version

    for version in v1.2.3 1.2/3 ""; do
        CreateReleaseSite 1.2.3
        RunPublishPages --version="${version}" "${sandbox}/site-1.2.3" "${sandbox}/published"
        ExpectStatus "${USAGE_ERROR}"
        ExpectStderrContains "error: expected a version that starts with a digit"
    done

    ExpectNotInstalled "${sandbox}/published"
}

function TestPublishPagesRequiresDirectories()
{
    CreateReleaseSite 1.2.3
    RunPublishPages --version=1.2.3 "${sandbox}/site-1.2.3"
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: expected the site and the published site"
    ExpectNotInstalled "${sandbox}/published"
}

# Two builds of the same commit yield the same files, so that anyone can verify
# a release artifact. The pacman package records the directories of its build,
# so only a build at the same paths reproduces it.
function TestPackagesAreReproducible()
{
    RequireCommands dpkg-buildpackage dh || return

    RunJust deb --version="${PACKAGE_VERSION}" --output="${sandbox}/first"
    RunJust tarball --version="${PACKAGE_VERSION}" --output="${sandbox}/first"
    sleep 1
    RunJust deb --version="${PACKAGE_VERSION}" --output="${sandbox}/second"
    RunJust tarball --version="${PACKAGE_VERSION}" --output="${sandbox}/second"
    ExpectStatus 0
    ExpectSameContents "${sandbox}/second/${DEB}" "${sandbox}/first/${DEB}"
    ExpectSameContents "${sandbox}/second/${TARBALL}" "${sandbox}/first/${TARBALL}"
}

# Completes the last of the given words of a command line in the test
# repository, with the completion installed below ~/.local of a home directory
# in the sandbox, where bash-completion loads it on demand. Stores the
# candidates in stdout, one per line without the trailing space that ends a
# complete word.
function Complete()
{
    RunJust install-bash-completion --prefix="${sandbox}/home/.local"

    # shellcheck disable=SC2016 # the inner shell expands the variables
    (cd "${repo}" && HOME="${sandbox}/home" \
        env --unset=BASH_COMPLETION_USER_DIR --unset=XDG_DATA_HOME \
        timeout "${HANG_TIMEOUT}" bash --norc --noprofile -c '
            source "$1"
            shift
            COMP_WORDS=("$@")
            COMP_CWORD=$(($# - 1))
            COMP_LINE="$*"
            COMP_POINT=${#COMP_LINE}
            _completion_loader "$1"
            spec="$(complete -p "$1")" || exit 1
            function="${spec##* -F }"
            function="${function%% *}"
            "${function}" "$1" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD - 1]}"
            printf "%s\n" "${COMPREPLY[@]%" "}"
        ' completion "${BASH_COMPLETION}" "$@") \
        >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
}

function TestCompletesLongOptions()
{
    Complete git purge-branches --
    ExpectStatus 0
    ExpectStdout --dry-run --equivalent --help --interactive
}

function TestCompletesLongOptionsForDash()
{
    Complete git purge-branches -
    ExpectStatus 0
    ExpectStdout --dry-run --equivalent --help --interactive
}

function TestCompletesOptionWithPrefix()
{
    Complete git purge-branches --e
    ExpectStatus 0
    ExpectStdout --equivalent
}

function TestCompletesBranchAsCommit()
{
    Git branch feature
    Complete git purge-branches f
    ExpectStatus 0
    ExpectStdout feature
}

function TestCompletesTagAsCommit()
{
    Git tag v1
    Complete git purge-branches v
    ExpectStatus 0
    ExpectStdout v1
}

function TestCompletesCommitAfterOption()
{
    Git branch feature
    Complete git purge-branches -n f
    ExpectStatus 0
    ExpectStdout feature
}

function TestCompletesCommitAfterDoubleDash()
{
    Git branch feature
    Complete git purge-branches -- f
    ExpectStatus 0
    ExpectStdout feature
}

function TestCompletesNoOptionAfterDoubleDash()
{
    Complete git purge-branches -- --
    ExpectStatus 0
    ExpectStdout ""
}

function TestCompletesOptionOfStandaloneCommand()
{
    Complete git-purge-branches --e
    ExpectStatus 0
    ExpectStdout --equivalent
}

function TestCompletesCommitOfStandaloneCommand()
{
    Git branch feature
    Complete git-purge-branches f
    ExpectStatus 0
    ExpectStdout feature
}

# Completes the given command line in zsh in the test repository, with the
# completion installed below a prefix whose functions directory is in front of
# fpath and the script in PATH, as the completion of git requires to list
# purge-branches as a command. Stores the matches in stdout, one per line in
# sorted order.
function CompleteZsh()
{
    local prefix="${sandbox}/prefix"
    local completion_dir="${prefix}/${INSTALLED_ZSH_COMPLETION%/*}"

    RunJust install-zsh-completion --prefix="${prefix}"

    (cd "${repo}" && PATH="${ROOT_DIR}:${PATH}" timeout "${HANG_TIMEOUT}" \
        "${ROOT_DIR}/tests/complete.zsh" "${completion_dir}" "$*") \
        >"${sandbox}/stdout" 2>"${sandbox}/stderr"
    status=$?
}

function TestZshCompletesCommand()
{
    CompleteZsh git purge-
    ExpectStatus 0
    ExpectStdout purge-branches
}

function TestZshCompletesLongOptions()
{
    CompleteZsh git purge-branches --
    ExpectStatus 0
    ExpectStdout --dry-run --equivalent --help --interactive
}

function TestZshCompletesShortAndLongOptions()
{
    CompleteZsh git purge-branches -
    ExpectStatus 0
    ExpectStdout --dry-run --equivalent --help --interactive -e -h -i -n
}

function TestZshCompletesOptionWithPrefix()
{
    CompleteZsh git purge-branches --e
    ExpectStatus 0
    ExpectStdout --equivalent
}

function TestZshOmitsGivenOption()
{
    CompleteZsh git purge-branches -n --
    ExpectStatus 0
    ExpectStdout --equivalent --help --interactive
}

function TestZshCompletesBranchAsCommit()
{
    Git branch topic
    CompleteZsh git purge-branches to
    ExpectStatus 0
    ExpectStdout topic
}

function TestZshCompletesTagAsCommit()
{
    Git tag v1
    CompleteZsh git purge-branches v
    ExpectStatus 0
    ExpectStdout v1
}

function TestZshCompletesCommitAfterOption()
{
    Git branch topic
    CompleteZsh git purge-branches -n to
    ExpectStatus 0
    ExpectStdout topic
}

function TestZshCompletesCommitAfterDoubleDash()
{
    Git branch topic
    CompleteZsh git purge-branches -- to
    ExpectStatus 0
    ExpectStdout topic
}

# A file of the same prefix shows a fallback to the completion of files.
function TestZshCompletesNoSecondCommit()
{
    Git branch topic
    touch "${repo}/toolbox"
    CompleteZsh git purge-branches topic to
    ExpectStatus 0
    ExpectStdout ""
}

function TestZshCompletesNothingAfterHelp()
{
    Git branch topic
    CompleteZsh git purge-branches --help ''
    ExpectStatus 0
    ExpectStdout ""
}

function TestZshCompletesOptionOfStandaloneCommand()
{
    CompleteZsh git-purge-branches --e
    ExpectStatus 0
    ExpectStdout --equivalent
}

function TestZshCompletesCommitOfStandaloneCommand()
{
    Git branch topic
    CompleteZsh git-purge-branches to
    ExpectStatus 0
    ExpectStdout topic
}

# Completes the given command line in fish in the test repository, with the
# completion installed below a prefix whose vendor completions directory is in
# front of fish_complete_path and the script in PATH, as the completion of git
# requires to forward git purge-branches to it. Stores the matches without
# their descriptions in stdout, one per line in sorted order.
function CompleteFish()
{
    local prefix="${sandbox}/prefix"
    local completion_dir="${prefix}/${INSTALLED_FISH_COMPLETION%/*}"

    RunJust install-fish-completion --prefix="${prefix}"

    # shellcheck disable=SC2016 # fish expands the variables
    (cd "${repo}" && PATH="${ROOT_DIR}:${PATH}" timeout "${HANG_TIMEOUT}" \
        fish --no-config -c '
            set --prepend fish_complete_path $argv[1]
            complete --do-complete $argv[2]
        ' "${completion_dir}" "$*") \
        >"${sandbox}/completions" 2>"${sandbox}/stderr"
    status=$?

    local word="${*: -1}"
    local -a completions
    local completion
    local match

    readarray -t completions <"${sandbox}/completions"

    # Each completion is a match and a description separated by a tab. Some
    # releases of fish, such as 4.2, also list matches that contain the word
    # only as a subsequence, such as --help for --e, which the pager ranks
    # below the matches that start with the word.
    for completion in "${completions[@]}"; do
        match="${completion%%$'\t'*}"

        if [[ ${match} == "${word}"* ]]; then
            echo "${match}"
        fi
    done >"${sandbox}/matches"

    LC_ALL=C sort --output="${sandbox}/stdout" "${sandbox}/matches"
}

function TestFishCompletesLongOptions()
{
    CompleteFish git purge-branches --
    ExpectStatus 0
    ExpectStdout --dry-run --equivalent --help --interactive
}

function TestFishCompletesOptionWithPrefix()
{
    CompleteFish git purge-branches --e
    ExpectStatus 0
    ExpectStdout --equivalent
}

function TestFishOmitsGivenOptions()
{
    CompleteFish git purge-branches -n -e --
    ExpectStatus 0
    ExpectStdout --help --interactive
}

function TestFishCompletesBranchAsCommit()
{
    Git branch topic
    CompleteFish git purge-branches to
    ExpectStatus 0
    ExpectStdout topic
}

function TestFishCompletesTagAsCommit()
{
    Git tag v1
    CompleteFish git purge-branches v
    ExpectStatus 0
    ExpectStdout v1
}

function TestFishCompletesCommitAfterOption()
{
    Git branch topic
    CompleteFish git purge-branches -n to
    ExpectStatus 0
    ExpectStdout topic
}

# A file of the same prefix shows a fallback to the completion of files.
function TestFishCompletesNoSecondCommit()
{
    Git branch topic
    touch "${repo}/toolbox"
    CompleteFish git purge-branches topic to
    ExpectStatus 0
    ExpectStdout ""
}

# The completion of git offers its own --help for every git command line, so
# only the standalone command shows that no option follows --help.
function TestFishCompletesNoOptionAfterHelp()
{
    CompleteFish git-purge-branches --help --
    ExpectStatus 0
    ExpectStdout ""
}

# The completion of git lists no refs if --help or -h is on the line, since it
# takes either for a global option of git, but it lists them for a bundle.
function TestFishCompletesNothingAfterHelp()
{
    Git branch topic
    CompleteFish git-purge-branches -nh ''
    ExpectStatus 0
    ExpectStdout ""
}

function TestFishCompletesOptionOfStandaloneCommand()
{
    CompleteFish git-purge-branches --e
    ExpectStatus 0
    ExpectStdout --equivalent
}

function TestFishCompletesCommitOfStandaloneCommand()
{
    Git branch topic
    CompleteFish git-purge-branches to
    ExpectStatus 0
    ExpectStdout topic
}

function Run()
{
    local name="$1"
    test_failed=0
    test_skipped=0
    ((++tests))

    SetUp
    "${name}"
    TearDown

    if [[ ${test_failed} -ne 0 ]]; then
        echo "FAIL ${name}"
        ((++failures))
    elif [[ ${test_skipped} -ne 0 ]]; then
        echo "SKIP ${name}"
        ((++skipped))
    else
        echo "PASS ${name}"
    fi
}

Run TestDeletesMergedBranch
Run TestSucceedsWithoutMergedBranches
Run TestKeepsUnmergedBranch
Run TestKeepsBranchOfOtherWorktree
Run TestKeepsCurrentBranchOfLinkedWorktree
Run TestDeletesBranchWithPlusInName
Run TestDeletesBranchSharingNameWithTag
Run TestKeepsBranchAheadOfUpstream
Run TestIgnoresColorConfiguration
Run TestKeepsBranchGivenAsCommit
Run TestKeepsBranchGivenAsFullRefName
Run TestDeletesBranchAtGivenTag
Run TestDeletesBranchNamedLikeGivenTag
Run TestKeepsRebasedBranchByDefault
Run TestDeletesRebasedBranchWithEquivalent
Run TestDeletesBranchRebasedOntoGivenCommit
Run TestDeletesRebasedBranchFromSubdirectoryWithEquivalent
Run TestKeepsPartlyRebasedBranchWithEquivalent
Run TestKeepsBranchOfEmptyCommitsWithEquivalent
Run TestKeepsBranchWithChangingMergeWithEquivalent
Run TestKeepsRebasedBranchOfOtherWorktreeWithEquivalent
Run TestDeletesRebasedBranchWhenMergedBranchIsRefused
Run TestReportsFailureToDeleteRebasedBranch
Run TestPrintsHowToRestoreDeletedBranches
Run TestRestoreHintOmitsRefusedBranches
Run TestPrintsNoRestoreHintWithoutDeletedBranches
Run TestDefaultsToDefaultBranchOfOrigin
Run TestGivenCommitOverridesDefaultBranchOfOrigin
Run TestDryRunDefaultsToDefaultBranchOfOrigin
Run TestInteractiveDeletesAfterYes
Run TestInteractiveAcceptsYesInAnyCase
Run TestInteractiveKeepsBranchesAfterNo
Run TestInteractiveKeepsBranchesWithoutAnswer
Run TestInteractiveAsksNothingWithoutBranches
Run TestInteractiveDryRunAsksNothing
Run TestDryRunListsMergedBranches
Run TestDryRunListsRebasedBranchesWithEquivalent
Run TestDryRunOmitsRebasedBranchesByDefault
Run TestAcceptsBundledShortOptions
Run TestAcceptsBundledShortOptionsInEitherOrder
Run TestAcceptsOptionsAfterCommit
Run TestHelpPrintsUsage
Run TestRejectsUnknownOption
Run TestRejectsUnknownOptionInBundle
Run TestRejectsSecondCommit
Run TestKeepsMergedBranchExemptByConfig
Run TestKeepsRebasedBranchExemptByConfig
Run TestKeepsDefaultBranchOfRemote
Run TestKeepsDefaultBranchOfEachRemote
Run TestKeepsBranchesMatchingKeepPatterns
Run TestKeepsRebasedBranchMatchingKeepPattern
Run TestDryRunOmitsProtectedBranches
Run TestDryRunOmitsExemptBranches
Run TestDeletesBranchWithDeleteMergedTrue
Run TestKeepsBranchExemptByConfigSpelledNo
Run TestKeepsExemptBranchWithDotInName
Run TestKeepsExemptBranchWithSlashInName
Run TestReportsInvalidDeleteMerged
Run TestReportsInvalidCommit
Run TestReportsFailureOutsideRepository
Run TestInstallInstallsAllBelowPrefix
Run TestInstallAcceptsPrefixWithSpace
Run TestInstallDefaultsToLocalOfHomeWithoutRoot
Run TestInstallDefaultsToUsrLocalWithRoot
Run TestInstallStagesBelowDestdir
Run TestInstallRejectsRelativePrefix
Run TestInstallScriptRequiresPrefix
Run TestInstallScriptRejectsUnknownComponent
Run TestInstallCompletionsInstallsOnlyCompletions
Run TestInstallBashCompletionInstallsOnlyIt
Run TestInstallZshCompletionInstallsOnlyIt
Run TestInstallFishCompletionInstallsOnlyIt
Run TestUninstallRemovesInstalledFiles
Run TestUninstallKeepsOtherFiles
Run TestUninstallSucceedsWithoutInstalledFiles
Run TestUninstallDefaultsToLocalOfHomeWithoutRoot
Run TestUninstallDefaultsToUsrLocalWithRoot
Run TestUninstallCompletionsRemovesOnlyCompletions
Run TestUninstallBashCompletionRemovesOnlyIt
Run TestUninstallZshCompletionRemovesOnlyIt
Run TestUninstallFishCompletionRemovesOnlyIt
Run TestDebHasControlFields
Run TestDebInstallsFilesBelowUsr
Run TestDebHasModesUnderRestrictiveUmask
Run TestDebHasChangelogOfRelease
Run TestDebContainsSources
Run TestTarballHasInstallLayout
Run TestTarballContainsSources
Run TestPackagesRejectVersionWithoutLeadingDigit
Run TestPackagesRejectVersionWithHyphen
Run TestPackageScriptRejectsUnknownFormat
Run TestVersionOfTaggedCommit
Run TestVersionOfCommitAfterTag
Run TestVersionWithoutTag
Run TestVersionOfArchive
Run TestVersionOfArchiveWithoutTag
Run TestDateOfCheckoutAndArchive
Run TestMakepkgBuildsTaggedCheckout
Run TestMakepkgBuildsArchive
Run TestPackagesDefaultToVersionOfSources
Run TestPackagesBuildFromArchive
Run TestPacmanHasPackageInfo
Run TestPacmanInstallsFilesBelowUsr
Run TestPacmanContainsSources
Run TestPagesRenderManualPage
Run TestPagesSetLiteralInputInMonospace
Run TestPagesHighlightExamples
Run TestPagesFollowDarkColorScheme
Run TestPagesNameVersion
Run TestPagesLinkToProject
Run TestPagesServeInstallScript
Run TestPagesLinkGitCommandsToGitDocumentation
Run TestPagesLinkOptionsAndSections
Run TestManPageNamesReferencesWithoutLinks
Run TestPackagesAreReproducible
Run TestPublishPagesAddsFirstRelease
Run TestPublishPagesKeepsEarlierReleases
Run TestPublishPagesRepublishesRelease
Run TestPublishPagesKeepsOtherFiles
Run TestPublishPagesRejectsInvalidVersion
Run TestPublishPagesRequiresDirectories
Run TestGetInstallsLatestRelease
Run TestGetInstallsGivenVersionBelowPrefix
Run TestGetDefaultsToUsrLocalWithRoot
Run TestGetRejectsTamperedTarball
Run TestGetRejectsTarballWithoutChecksum
Run TestGetReportsMissingLatestRelease
Run TestGetReportsMissingRelease
Run TestGetUninstallsRelease
Run TestGetInstallsWithBsdtar
Run TestGetRejectsRelativePrefix
Run TestCompletesLongOptions
Run TestCompletesLongOptionsForDash
Run TestCompletesOptionWithPrefix
Run TestCompletesBranchAsCommit
Run TestCompletesTagAsCommit
Run TestCompletesCommitAfterOption
Run TestCompletesCommitAfterDoubleDash
Run TestCompletesNoOptionAfterDoubleDash
Run TestCompletesOptionOfStandaloneCommand
Run TestCompletesCommitOfStandaloneCommand
Run TestZshCompletesCommand
Run TestZshCompletesLongOptions
Run TestZshCompletesShortAndLongOptions
Run TestZshCompletesOptionWithPrefix
Run TestZshOmitsGivenOption
Run TestZshCompletesBranchAsCommit
Run TestZshCompletesTagAsCommit
Run TestZshCompletesCommitAfterOption
Run TestZshCompletesCommitAfterDoubleDash
Run TestZshCompletesNoSecondCommit
Run TestZshCompletesNothingAfterHelp
Run TestZshCompletesOptionOfStandaloneCommand
Run TestZshCompletesCommitOfStandaloneCommand
Run TestFishCompletesLongOptions
Run TestFishCompletesOptionWithPrefix
Run TestFishOmitsGivenOptions
Run TestFishCompletesBranchAsCommit
Run TestFishCompletesTagAsCommit
Run TestFishCompletesCommitAfterOption
Run TestFishCompletesNoSecondCommit
Run TestFishCompletesNoOptionAfterHelp
Run TestFishCompletesNothingAfterHelp
Run TestFishCompletesOptionOfStandaloneCommand
Run TestFishCompletesCommitOfStandaloneCommand

echo "${failures} of ${tests} tests failed, ${skipped} skipped"
[[ ${failures} -eq 0 ]]
