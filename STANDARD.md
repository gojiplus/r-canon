# The standard

One versioned standard for the R packages. Changing the fleet's mind is a pull
request to this file and the workflows beside it.

This is deliberately smaller than [py-canon](https://github.com/gojiplus/py-canon).
R already has good, better-maintained answers for most of what py-canon carries:
`usethis` and `rcompendium` scaffold packages, `r-lib/actions` runs the CI steps,
`pkgdown` builds the site, `lintr` and `styler` handle style, `R CMD check --as-cran`
is the conformance bar. What R has no answer for is keeping a *set* of repos on
one standard, because `r-lib/actions` ships example workflows to **copy** rather
than workflows to **reference**. Copies drift. That gap, and only that gap, is
what lives here.

## What every package does

| | |
|---|---|
| CI | References the five reusable workflows below, pinned to `@v1` |
| Workflow filenames | `R-CMD-check.yml`, `pkgdown.yml`, `test-coverage.yml`, `link-check.yml`, `lint.yml` — exactly these |
| Checks on | Ubuntu release/devel/oldrel-1, macOS release, Windows release |
| Check bar | `R CMD check --as-cran` clean; warnings fail the build |
| Tests | `testthat`, edition 3, under `tests/testthat/` |
| Lint | The canonical `.lintr` from this repo, byte-identical, enforced in CI by `lint.yml` — never in the test suite |
| Docs | roxygen2, and a `pkgdown` site deployed to `gh-pages` |
| Version | Semantic, in `DESCRIPTION`, matching a `v`-prefixed git tag; `.9xxx` dev versions between releases |
| License | Declared in `DESCRIPTION` with a `LICENSE` file |
| News | `NEWS.md`, newest first, one section per released version, a `(development version)` header on top between releases |

## Consuming it

Five workflow files, a few lines each, plus one copied `.lintr`. Everything
else lives here.

`.github/workflows/R-CMD-check.yml`:

```yaml
name: R-CMD-check
on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]
jobs:
  check:
    uses: gojiplus/r-canon/.github/workflows/reusable-check.yml@v1
```

`.github/workflows/pkgdown.yml`:

```yaml
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
    permissions:
      contents: write
    uses: gojiplus/r-canon/.github/workflows/reusable-pkgdown.yml@v1
```

That `permissions` block is required, not decorative. A called workflow cannot
grant itself more than the caller has, and these repos default to a read-only
token, so the deploy to `gh-pages` needs the caller to ask for write. Omit it
and the run fails at startup in zero seconds with no log to read.

`.github/workflows/test-coverage.yml`:

```yaml
name: test-coverage
on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]
jobs:
  coverage:
    uses: gojiplus/r-canon/.github/workflows/reusable-coverage.yml@v1
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

The `secrets:` block is optional. Without a token, coverage is still computed,
printed and kept as a build artifact; only the Codecov upload is skipped.

`.github/workflows/lint.yml`:

```yaml
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
    uses: gojiplus/r-canon/.github/workflows/reusable-lint.yml@v1
```

`.github/workflows/link-check.yml`:

```yaml
name: link-check
on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]
  schedule:
    - cron: "0 6 * * 1"
  workflow_dispatch:
permissions:
  contents: read
jobs:
  links:
    uses: gojiplus/r-canon/.github/workflows/reusable-link-check.yml@v1
```

The `permissions` block here does the opposite job to the one on `pkgdown`.
That one *grants* write so a deploy can happen; this one *caps* the token at
read. A called workflow can only narrow what its caller holds, so the caller is
where the ceiling is set, and a repo whose default token is read-write would
otherwise hand one to a job that only ever reads files.

The `schedule` is not decorative either. External links rot without anyone
committing, so a package that is finished — which is most of them — would never
find out.

This does not duplicate `urlchecker` or the URL step in `R CMD check --as-cran`.
Both read R's own URL database, which collects link *targets* and never image
sources, so a README badge is invisible to them. tubern's R-CMD-check badge
pointed at a renamed workflow and returned 404 for months while `urlchecker`
reported "All URLs are correct!" against the same tree. Keep using `urlchecker`
for `\url{}` in `Rd` and for its redirect fixes; it answers a different question.

## Lint and style

The config is one canonical `.lintr`, at the root of this repo. It is lintr's
tidyverse defaults with exactly two deviations, both measured from the fleet
rather than invented:

- **`line_length_linter(100L)`.** Three fleet configs had already chosen 100,
  and two more disabled the linter entirely rather than live with 80. 100 is
  the strictest bound the fleet has ever voluntarily held.
- **`object_name_linter` admits `dotted.case` beside `snake_case`.** Exported
  names in the older packages cannot be snake_cased without breaking their
  users' code, and one repo had already encoded exactly this compromise. The
  alternative was what three repos actually did: disable the linter outright.

Everything else stays at the defaults — including the trailing-whitespace,
indentation and return linters that four repos had switched off. Those are a
one-time `styler::style_pkg()` cost, not an ongoing one, and `styler` with
tidyverse defaults is the prescribed fixer for exactly that reason. It is not
CI-enforced this round: lintr gates the load-bearing issues, and a formatter
check is a second, sometimes-disagreeing authority.

Unlike the workflows, the config is **materialized**: lintr reads its own file
and nothing can make it read a remote one, so every repo carries a copy and a
copy drifts. Two controls compensate. `reusable-lint.yml` diffs the repo's
`.lintr` against this repo's on every run, so a locally softened config goes
red the next push; and `drift.R` audits the same thing across checkouts. This
is the one place the "a copied file would just be drift" rule below bends —
with the diff as the guard, the copy cannot drift silently.

Lint runs in CI and **never in the test suite**. A
`tests/testthat/test-pkg-style.R` calling `lintr::expect_lint_free()` — four
fleet repos had one — is drift: lintr itself skips `expect_lint_free()` on
CRAN, so the test is dead weight exactly where tests matter, and everywhere
else it makes other machines' lintr versions into style oracles for
`R CMD check`. `adopt.sh` deletes the file; `drift.R` fails a repo that has
one. lintr does not need to sit in `Suggests` for CI to run it.

## Inputs, and why there are so few

The check matrix is **not** an input. It is the five configurations CRAN runs,
and a package needing a different set needs a conversation rather than a knob —
a standard you can configure your way out of is not a standard. Drift re-enters
through options. The lint workflow has no inputs at all, for the same reason.

The inputs that do exist cover the places packages legitimately differ:

| workflow | input | when to set it |
|---|---|---|
| check | `build-args` | A package with no vignettes can drop `--compact-vignettes` and its ghostscript dependency |
| check | `error-on` | Temporarily loosening to `"error"` while a warning is fixed. Say in a comment when it goes back |
| check | `extra-packages` | A package whose checks need something beyond `rcmdcheck` |
| pkgdown | `extra-packages` | Same, for the site build |
| link-check | `paths` | A package whose prose lives somewhere other than the default set. One glob per line — a bare directory name matches nothing and still exits 0 |
| link-check | `exclude` | URL regexes to skip. For service endpoints that appear in source as string constants: an API base URL answers 404 to an unauthenticated GET by design |

## Action pinning

Every `uses:` in these workflows names a commit SHA, with the human-readable
version beside it in a comment:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

A tag like `@v7` is a label its owner can repoint at any time, including an
owner whose account has been taken over. Because the fleet runs these workflows
rather than copying them, code swapped in behind such a tag would execute in
every R repo at once, against their secrets, with no commit landing in any of
them. A SHA names one immutable tree, so nothing changes underneath us.

This is only safe because Dependabot is configured here for `github-actions`
and rewrites both the SHA and its comment when a real release ships. Pinning
without that automation is worse than floating tags: the pins never move and
the fleet quietly runs unpatched actions forever.

## Versioning

Tags version the workflows together. Repos reference the moving major tag `v1`,
so a fix here reaches every repo on its next run. Breaking changes to the
standard — anything that would make a currently-green repo fail — bump to `v2`,
and repos move over deliberately. Each release is recorded in
[CHANGELOG.md](CHANGELOG.md).

## Drift

`tools/drift.R` audits a set of checkouts against this file and exits non-zero
if any has drifted:

```bash
Rscript tools/drift.R ~/Documents/GitHub
```

It reports whether each repo references `@v1`, uses the canonical filenames,
carries the canonical `.lintr` unmodified, has `testthat` at **edition 3**,
`pkgdown`, a `LICENSE` and a `NEWS.md`, keeps lint out of the test suite, and
whether its `DESCRIPTION` version matches its latest tag — exactly, or as a
`.9xxx` dev version on top of it. A repo with no tags at all is pre-release,
not drifted. Leftover `CRAN-SUBMISSION`/`CRAN-RELEASE` files are noted without
failing, since a submission legitimately carries one while it is pending.
`rhub.yaml` is a sanctioned extra workflow: `rhub::rhub_setup()` writes it and
the release process depends on it.

The edition check earns its place: the table above has always required edition 3,
and nothing verified it. A package can sit on edition 2 — still calling
`context()` and `expect_that(is_a())`, both deprecated — and pass as `tests: yes`.
Three repos were doing exactly that when the check was added. A rule the standard
states but does not audit is a rule the fleet drifts away from silently, which is
the whole failure mode this repo exists to prevent.

## What is deliberately not here

- **A package template.** `usethis::create_package()` and `rcompendium` already
  do this, and better.
- **A conformance CLI.** `R CMD check --as-cran`, `lintr` and `goodpractice`
  cover the per-package checks. `pkgcheck` is worth knowing about but cannot
  serve as our standard: it is extensible via `extra_env` yet its built-in
  checks cannot be disabled, and `pkgchk_branch_is_master` alone fails every
  repo here.
- **Shared roxygen or pkgdown config.** There is no import mechanism for these
  the way `py_canon.sphinx` works for Sphinx, and faking one with a copied file
  would just be drift again. (The `.lintr` is the deliberate exception: it too
  is a copy, but the lint workflow diffs it against canon on every run, which
  a roxygen or pkgdown config has no equivalent of.)
