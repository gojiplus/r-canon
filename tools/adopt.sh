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
REF="v1"
CANON_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ $# -eq 0 ]; then
  echo "usage: $(basename "$0") <repo-dir> [repo-dir ...]" >&2
  exit 2
fi

for repo in "$@"; do
  if [ ! -f "$repo/DESCRIPTION" ]; then
    echo "skip $repo: no DESCRIPTION, not an R package" >&2
    continue
  fi

  name=$(basename "$repo")
  wf="$repo/.github/workflows"
  mkdir -p "$wf"

  # Anything already there is either a copy of what we are about to reference
  # or something bespoke. Either way it goes; git keeps it if it is wanted back.
  existing=()
  while IFS= read -r -d '' f; do
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
    # A called workflow cannot grant itself more than the caller has, and the
    # default token here is read-only. The deploy to gh-pages needs write.
    permissions:
      contents: write
    uses: $CANON/.github/workflows/reusable-pkgdown.yml@$REF
YAML

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

  if [ ! -f "$repo/_pkgdown.yml" ] && [ ! -f "$repo/_pkgdown.yaml" ] &&
     [ ! -f "$repo/pkgdown/_pkgdown.yml" ]; then
    echo "$name: note -- no pkgdown config; the site job will build a default one"
  fi
done

echo
echo "Review the diffs, then commit. Nothing has been committed or pushed."
