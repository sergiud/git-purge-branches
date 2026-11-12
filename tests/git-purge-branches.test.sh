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
# Seconds after which a run of the script counts as hung. A run takes
# milliseconds, so the limit only ends runs that never finish, even on a
# loaded machine.
readonly HANG_TIMEOUT=60

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
# arguments and stores its exit status, which is that of timeout if the run
# hangs.
function RunPurgeIn()
{
    local directory="$1"
    shift

    (cd "${directory}" && timeout "${HANG_TIMEOUT}" /bin/bash "${SCRIPT}" "$@") \
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

# Runs a dry run with the given bundle of -e and -n.
function ExpectBundledOptionsAccepted()
{
    local options="$1"

    Git branch merged
    CreateRebasedBranch rebased master
    RunPurge "${options}"
    ExpectStatus 0
    ExpectStdout merged rebased
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

function TestDryRunOmitsExemptBranches()
{
    Git branch merged
    Git branch exempt
    CreateRebasedBranch rebased master
    Git config branch.exempt.deleteMerged false
    Git config branch.rebased.deleteMerged false
    RunPurge --dry-run --equivalent
    ExpectStatus 0
    ExpectStdout merged
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
    printf '#!/bin/sh\necho %s\n' "${uid}" > "${sandbox}/fake-bin/id"
    chmod +x "${sandbox}/fake-bin/id"
}

# Runs the given recipe of the justfile with its arguments and stores its exit
# status. The home directory is in the sandbox, so that the default prefix of a
# user never points to the real one.
function RunJust()
{
    (HOME="${sandbox}/home" PATH="${sandbox}/fake-bin:${PATH}" \
        timeout "${HANG_TIMEOUT}" just --justfile "${ROOT_DIR}/justfile" "$@") \
        > "${sandbox}/stdout" 2> "${sandbox}/stderr"
    status=$?
}

function RunInstallScript()
{
    timeout "${HANG_TIMEOUT}" "${ROOT_DIR}/scripts/install.sh" "$@" \
        > "${sandbox}/stdout" 2> "${sandbox}/stderr"
    status=$?
}

function ExpectInstalledFile()
{
    local path="$1"
    local mode="$2"
    local source="$3"
    local actual_mode

    if [[ ! -f ${path} ]]
    then
        Fail "expected installed file '${path}'"
        return
    fi

    actual_mode="$(stat --format=%a "${path}")"

    if [[ ${actual_mode} != "${mode}" ]]
    then
        Fail "expected mode ${mode} of '${path}', got ${actual_mode}"
    fi

    if ! cmp --quiet "${path}" "${source}"
    then
        Fail "expected '${path}' to equal '${source}'"
    fi
}

function ExpectNotInstalled()
{
    local path="$1"

    if [[ -e ${path} ]]
    then
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

    if [[ ! -f ${other_completion} ]]
    then
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
        > "${sandbox}/stdout" 2> "${sandbox}/stderr"
    status=$?
}

function TestCompletesLongOptions()
{
    Complete git purge-branches --
    ExpectStatus 0
    ExpectStdout --dry-run --equivalent --help
}

function TestCompletesLongOptionsForDash()
{
    Complete git purge-branches -
    ExpectStatus 0
    ExpectStdout --dry-run --equivalent --help
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
        > "${sandbox}/stdout" 2> "${sandbox}/stderr"
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
    ExpectStdout --dry-run --equivalent --help
}

function TestZshCompletesShortAndLongOptions()
{
    CompleteZsh git purge-branches -
    ExpectStatus 0
    ExpectStdout --dry-run --equivalent --help -e -h -n
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
    ExpectStdout --equivalent --help
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
        > "${sandbox}/completions" 2> "${sandbox}/stderr"
    status=$?

    local word="${*: -1}"
    local -a completions
    local completion
    local match

    readarray -t completions < "${sandbox}/completions"

    # Each completion is a match and a description separated by a tab. Some
    # releases of fish, such as 4.2, also list matches that contain the word
    # only as a subsequence, such as --help for --e, which the pager ranks
    # below the matches that start with the word.
    for completion in "${completions[@]}"; do
        match="${completion%%$'\t'*}"

        if [[ ${match} == "${word}"* ]]; then
            echo "${match}"
        fi
    done > "${sandbox}/matches"

    LC_ALL=C sort --output="${sandbox}/stdout" "${sandbox}/matches"
}

function TestFishCompletesLongOptions()
{
    CompleteFish git purge-branches --
    ExpectStatus 0
    ExpectStdout --dry-run --equivalent --help
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
    ExpectStdout --help
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
Run TestAcceptsBundledShortOptions
Run TestAcceptsBundledShortOptionsInEitherOrder
Run TestAcceptsOptionsAfterCommit
Run TestHelpPrintsUsage
Run TestRejectsUnknownOption
Run TestRejectsUnknownOptionInBundle
Run TestRejectsSecondCommit
Run TestKeepsMergedBranchExemptByConfig
Run TestKeepsRebasedBranchExemptByConfig
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

echo "${failures} of ${tests} tests failed"
[[ ${failures} -eq 0 ]]
