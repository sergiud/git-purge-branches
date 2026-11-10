#!/bin/bash
#
# Tests for git-purge-branches. Each test runs the script in a new repository
# with the global and system Git configuration disabled, so the user's
# configuration cannot change the outcome.

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/git-purge-branches"
readonly SCRIPT
# Status of git when it runs outside a repository
readonly GIT_NOT_A_REPOSITORY=128

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

# Runs the script under test in the given directory and stores its exit
# status.
function RunPurgeIn()
{
    local directory="$1"

    (cd "${directory}" && /bin/bash "${SCRIPT}") \
        > "${sandbox}/stdout" 2> "${sandbox}/stderr"
    status=$?
}

function RunPurge()
{
    RunPurgeIn "${repo}"
}

# Creates a branch with a commit that the current branch lacks.
function CreateUnmergedBranch()
{
    local name="$1"

    Git switch -q -c "${name}"
    Git commit -q --allow-empty -m "${name}"
    Git switch -q -
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
Run TestReportsFailureOutsideRepository

echo "${failures} of ${tests} tests failed"
[[ ${failures} -eq 0 ]]
