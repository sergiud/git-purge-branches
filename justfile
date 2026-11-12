man_dir := "man/man1"

# Converts the AsciiDoc manual pages to troff below man, where man finds them
# while this directory is in PATH, and lints the result. groff exits with 0
# even if it warns, so any diagnostic fails the recipe.
man:
    #!/usr/bin/env bash
    set -euo pipefail
    asciidoctor --backend manpage --failure-level WARN --destination-dir {{ man_dir }} doc/man/*.adoc
    for page in {{ man_dir }}/*.1; do
        diagnostics="$(groff -man -rCHECKSTYLE=3 -ww -z "${page}" 2>&1)"
        if [[ -n ${diagnostics} ]]; then
            echo "error: groff diagnostics for ${page}:" >&2
            echo "${diagnostics}" >&2
            exit 1
        fi
    done

test:
    ./tests/git-purge-branches.test.sh
