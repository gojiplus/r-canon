#!/usr/bin/env bash
# Put a repo on the standard: write the five shims and the canonical .lintr,
# remove whatever CI was there before.
#
#   tools/adopt.sh ~/Documents/GitHub/bloomjoin
#   tools/adopt.sh ~/Documents/GitHub/{bloomjoin,dann,tubern}
#
# Writes files and stages the deletions. It does not commit or push -- look at
# the diff first, especially for a repo that had bespoke workflows worth
# reading before they go. Removals are deliberate, with no keep-list: extra
# workflows are what drift looks like from the outside, and the one legitimate
# counterexample so far (a repo's own statistical-tests workflow) is a call the
# human makes at the diff, which is exactly where this script sends them.

set -euo pipefail

CANON="gojiplus/r-canon"
REF="v2"
CANON_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ $# -eq 0 ]; then
  echo "usage: $(basename "$0") <repo-dir> [repo-dir ...]" >&2
  exit 2
fi

# Print the trailing `with:` block of a shim that already references the
# canonical reusable workflow named in $2, so rewriting the file does not
# discard it.
#
# The inputs a repo sets there are configuration, not drift: link-check
# exclude lists name the API endpoints that answer 404 to an unauthenticated
# GET, and dropping them turns the job red on the next push. Three repos lost
# theirs to this rewrite before the carry-over existed, and only caught it
# because a human read the diff.
#
# `secrets:` ends the block rather than joining it -- the coverage shim writes
# its own, and carrying a second copy would duplicate the key.
carry_inputs() {
  [ -f "$1" ] || return 0
  grep -q "$2" "$1" || return 0
  awk '
    /^[[:space:]]*secrets:[[:space:]]*$/ { keep = 0 }
    /^[[:space:]]*with:[[:space:]]*$/ { keep = 1 }
    keep { print }
  ' "$1"
}

for repo in "$@"; do
  if [ ! -f "$repo/DESCRIPTION" ]; then
    echo "skip $repo: no DESCRIPTION, not an R package" >&2
    continue
  fi

  name=$(basename "$repo")
  wf="$repo/.github/workflows"
  mkdir -p "$wf"

  carry_check=$(carry_inputs "$wf/R-CMD-check.yml" reusable-check.yml)
  carry_pkgdown=$(carry_inputs "$wf/pkgdown.yml" reusable-pkgdown.yml)
  carry_coverage=$(carry_inputs "$wf/test-coverage.yml" reusable-coverage.yml)
  carry_lint=$(carry_inputs "$wf/lint.yml" reusable-lint.yml)
  carry_links=$(carry_inputs "$wf/link-check.yml" reusable-link-check.yml)

  # Anything already there is either a copy of what we are about to reference
  # or something bespoke. Either way it goes; git keeps it if it is wanted back.
  #
  # Except the files drift.R names as legitimate. rhub.yaml is written by
  # rhub::rhub_setup() and the release checklist in STANDARD.md uses it;
  # statistical-tests.yml is guess's own, named there as the one bespoke
  # workflow the fleet has; sphinx-docs.yml is the alternative site build.
  # Deleting what the audit allows made this script and that one disagree
  # about the standard, which is the drift this repo exists to prevent.
  existing=()
  while IFS= read -r -d '' f; do
    case "${f##*/}" in
      rhub.yaml|rhub.yml|statistical-tests.yml|sphinx-docs.yml) continue ;;
    esac
    existing+=("$f")
  done < <(find "$wf" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null | sort -z)

  if [ ${#existing[@]} -gt 0 ]; then
    echo "$name: removing ${#existing[@]} existing workflow(s)"
    printf '    %s\n' "${existing[@]##*/}"
    rm -f "${existing[@]}"
  fi

  cat > "$wf/R-CMD-check.yml" <<YAML
name: R-CMD-check

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  check:
    uses: $CANON/.github/workflows/reusable-check.yml@$REF
YAML

  # At most one workflow may deploy. A sphinx-docs.yml that passes
  # deploy: true publishes the site, so the pkgdown shim would race it for the
  # same Pages deployment. One without it is a parallel build uploading an
  # artifact, which is how a package compares the two before switching, and
  # pkgdown stays the published site.
  if [ -f "$wf/sphinx-docs.yml" ] && grep -qE '^[[:space:]]*deploy:[[:space:]]*true[[:space:]]*$' "$wf/sphinx-docs.yml"; then
    echo "$name: deploys a Sphinx site; skipping the pkgdown shim"
    rm -f "$wf/pkgdown.yml"
  else
  cat > "$wf/pkgdown.yml" <<YAML
name: pkgdown

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]
  release:
    types: [published]
  workflow_dispatch:

jobs:
  pkgdown:
    # A called workflow cannot grant itself more than the caller has, so every
    # scope the site build and deploy use has to be granted here. Naming any
    # scope drops the rest to none, so contents has to be restated even though
    # it is the default -- omit it and the checkout fails.
    permissions:
      contents: read
      pages: write
      id-token: write
    uses: $CANON/.github/workflows/reusable-pkgdown.yml@$REF
YAML
  fi

  cat > "$wf/test-coverage.yml" <<YAML
name: test-coverage

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  coverage:
    uses: $CANON/.github/workflows/reusable-coverage.yml@$REF
    secrets:
      CODECOV_TOKEN: \${{ secrets.CODECOV_TOKEN }}
YAML

  cat > "$wf/lint.yml" <<YAML
name: lint

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

permissions:
  contents: read

jobs:
  lint:
    uses: $CANON/.github/workflows/reusable-lint.yml@$REF
YAML

  cat > "$wf/link-check.yml" <<YAML
name: link-check

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]
  # External links rot without a commit to trigger a rerun, so a dormant repo
  # would otherwise never find out.
  schedule:
    - cron: "0 6 * * 1"
  workflow_dispatch:

# The reusable workflow restricts itself to this as well, but a called workflow
# can only ever narrow what the caller holds -- so the caller is where the
# ceiling is actually set.
permissions:
  contents: read

jobs:
  links:
    uses: $CANON/.github/workflows/reusable-link-check.yml@$REF
YAML

  restore() {
    [ -n "$2" ] || return 0
    printf '%s\n' "$2" >> "$wf/$1"
    echo "$name: kept the inputs already set on $1"
  }
  restore R-CMD-check.yml "$carry_check"
  if [ -f "$wf/pkgdown.yml" ]; then
    restore pkgdown.yml "$carry_pkgdown"
  fi
  restore test-coverage.yml "$carry_coverage"
  restore lint.yml "$carry_lint"
  restore link-check.yml "$carry_links"

  # The lint config is materialized, not referenced -- lintr only reads its
  # own file. The canonical copy always wins; reusable-lint.yml diffs it
  # against canon on every run, so a softened local copy would fail there
  # anyway.
  if [ -f "$repo/.lintr" ] && ! cmp -s "$CANON_DIR/.lintr" "$repo/.lintr"; then
    echo "$name: replacing existing .lintr with the canonical one"
  fi
  cp "$CANON_DIR/.lintr" "$repo/.lintr"

  # .lintr is package infrastructure, not package payload. Writing it without
  # registering it earns a NOTE from R CMD check about a hidden file shipped
  # in error -- bloomjoin's .Rbuildignore was the first that did not already
  # happen to cover it.
  if [ -f "$repo/.Rbuildignore" ] && ! grep -qF '^\.lintr$' "$repo/.Rbuildignore"; then
    printf '^\\.lintr$\n' >> "$repo/.Rbuildignore"
    echo "$name: added ^\\.lintr\$ to .Rbuildignore"
  fi

  # The site is a build product. CI builds and publishes it, so a committed
  # docs/ is a second copy that goes stale silently -- tuber's sat three
  # releases behind the live site before anyone looked. R Packages (2e) ch. 19
  # reaches the same conclusion from the other direction.
  # Any spelling git already honours counts: a bare `docs` ignores the
  # directory just as well as `/docs/`, and appending a second entry beside it
  # would be noise in a file people read.
  if ! grep -qE '^/?docs/?$' "$repo/.gitignore" 2>/dev/null; then
    printf '\n# pkgdown output. Disposable local build product; CI builds and\n# publishes the definitive site.\n/docs/\n' >> "$repo/.gitignore"
    echo "$name: added /docs/ to .gitignore"
  fi
  if git -C "$repo" ls-files --error-unmatch docs >/dev/null 2>&1; then
    tracked=$(git -C "$repo" ls-files docs | wc -l | tr -d ' ')
    echo "$name: untracking $tracked committed pkgdown file(s) under docs/"
    git -C "$repo" rm -r --cached --quiet docs >/dev/null 2>&1 || true
  fi

  # Lint runs in CI, never in the test suite: lintr skips expect_lint_free()
  # on CRAN, and everywhere else the test makes other machines' lintr versions
  # into style oracles for R CMD check.
  style_test="$repo/tests/testthat/test-pkg-style.R"
  if [ -f "$style_test" ]; then
    echo "$name: removing tests/testthat/test-pkg-style.R (lint lives in CI now)"
    rm -f "$style_test"
    git -C "$repo" add -A tests/testthat/test-pkg-style.R >/dev/null 2>&1 || true
  fi

  git -C "$repo" add -A .github/workflows .lintr >/dev/null 2>&1 || true
  echo "$name: on $CANON@$REF"

  if [ -f "$wf/pkgdown.yml" ] &&
     [ ! -f "$repo/_pkgdown.yml" ] && [ ! -f "$repo/_pkgdown.yaml" ] &&
     [ ! -f "$repo/pkgdown/_pkgdown.yml" ]; then
    echo "$name: note -- no pkgdown config; the site job will build a default one"
  fi

  # The one part of adoption that is a repo setting rather than a file, and the
  # one that fails silently: with Pages still serving a branch, the deploy job
  # succeeds and publishes nothing anyone can see. Printed rather than run --
  # this script otherwise touches only the working tree.
  slug=$(git -C "$repo" remote get-url origin 2>/dev/null |
    sed -e 's#^git@github\.com:##' -e 's#^https://github\.com/##' -e 's#\.git$##' || true)
  if [ -n "$slug" ]; then
    echo "$name: point Pages at Actions, or the deploy publishes nowhere:"
    echo "    gh api -X PUT repos/$slug/pages -f build_type=workflow"
  fi
done

echo
echo "Review the diffs, then commit. Nothing has been committed or pushed."
