#!/bin/bash
#
# Tests for git-purge-branches. Each test runs the script in a new repository
# with the global and system Git configuration disabled, so the user's
# configuration cannot change the outcome.

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/git-purge-branches"
readonly SCRIPT
# Status of git when it runs outside a repository
readonly GIT_NOT_A_REPOSITORY=128
# Status of the script for invalid options or arguments
readonly USAGE_ERROR=2

failures=0
tests=0

function Git()
{
    git -C "${repo}" "$@"
}

function SetUp()
{
    sandbox="$(mktemp -d)"
    repo="${sandbox}/repo"

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
    rm -Rf "${sandbox}"
}

# Runs the script under test in the given directory with the remaining
# arguments and stores its exit status.
function RunPurgeIn()
{
    local directory="$1"
    shift

    (cd "${directory}" && /bin/bash "${SCRIPT}" "$@") \
        > "${sandbox}/stdout" 2> "${sandbox}/stderr"
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

    echo "${name}" > "${repo}/${name}"
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
    Git cherry-pick "${name}" > /dev/null
    Git switch -q master
}

function Fail()
{
    echo "    $*"
    test_failed=1
}

function ExpectStatus()
{
    local expected="$1"

    if [[ ${status} -ne ${expected} ]]
    then
        Fail "expected exit status ${expected}, got ${status}, stderr: '$(< "${sandbox}/stderr")'"
    fi
}

function ExpectBranches()
{
    local expected="$*"
    local actual
    actual="$(Git for-each-ref --format='%(refname:lstrip=2)' refs/heads/)"
    actual="${actual//$'\n'/ }"

    if [[ ${actual} != "${expected}" ]]
    then
        Fail "expected branches '${expected}', got '${actual}'"
    fi
}

function ExpectStdout()
{
    local expected="$*"
    local actual
    actual="$(< "${sandbox}/stdout")"
    actual="${actual//$'\n'/ }"

    if [[ ${actual} != "${expected}" ]]
    then
        Fail "expected stdout '${expected}', got '${actual}'"
    fi
}

function ExpectStderrContains()
{
    local expected="$1"

    if ! grep -qF -- "${expected}" "${sandbox}/stderr"
    then
        Fail "expected stderr to contain '${expected}', got '$(< "${sandbox}/stderr")'"
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
    Git merge -q --no-commit side > /dev/null 2>&1
    CommitFile resolution
    Git switch -q master
    CommitFile master-feature
    Git cherry-pick side feature^ > /dev/null
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

function TestDryRunListsMergedBranches()
{
    Git branch feature
    Git branch other
    RunPurge --dry-run
    ExpectStatus 0
    ExpectStdout feature other
    ExpectBranches feature master other
}

function TestDryRunListsRebasedBranchesWithEquivalent()
{
    Git branch merged
    CreateRebasedBranch rebased master
    RunPurge -n -e
    ExpectStatus 0
    ExpectStdout merged rebased
    ExpectBranches master merged rebased
}

function TestDryRunOmitsRebasedBranchesByDefault()
{
    Git branch merged
    CreateRebasedBranch rebased master
    RunPurge -n
    ExpectStatus 0
    ExpectStdout merged
    ExpectBranches master merged rebased
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

    if ! grep -qF -- '--equivalent' "${sandbox}/stdout"
    then
        Fail "expected usage with --equivalent on stdout, got '$(< "${sandbox}/stdout")'"
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

function TestRejectsSecondCommit()
{
    Git branch feature
    RunPurge HEAD feature
    ExpectStatus "${USAGE_ERROR}"
    ExpectStderrContains "error: expected at most 1 commit, got 2"
    ExpectBranches feature master
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

function Run()
{
    local name="$1"
    test_failed=0
    ((++tests))

    SetUp
    "${name}"
    TearDown

    if [[ ${test_failed} -eq 0 ]]
    then
        echo "PASS ${name}"
    else
        echo "FAIL ${name}"
        ((++failures))
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
Run TestDryRunListsMergedBranches
Run TestDryRunListsRebasedBranchesWithEquivalent
Run TestDryRunOmitsRebasedBranchesByDefault
Run TestAcceptsOptionsAfterCommit
Run TestHelpPrintsUsage
Run TestRejectsUnknownOption
Run TestRejectsSecondCommit
Run TestReportsInvalidCommit
Run TestReportsFailureOutsideRepository

echo "${failures} of ${tests} tests failed"
[[ ${failures} -eq 0 ]]
