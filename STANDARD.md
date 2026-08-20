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
- **`object_name_linter` admits `dotted.case` and `SNAKE_CASE` beside
  `snake_case`.** Exported names in the older packages cannot be snake_cased
  without breaking their users' code, and one repo had already encoded exactly
  this compromise; the alternative was what three repos actually did, which
  was to disable the linter outright. `SNAKE_CASE` covers package constants —
  `guess` keeps 33 of them in one file, and there is no version of "rename
  `VALID_RESPONSE_VALUES`" that improves that code.

Two paths are excluded because nobody writes them by hand: `R/RcppExports.R`
(Rcpp generates it) and `tests/testthat/_fixtures` (where `httptest2` records
API responses — it writes non-200 replies as `.R` files, and the virustotal
pilot found 15 lints inside one of them, none of which a human could fix).

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
| check | `not-cran` | Run the `skip_on_cran()` tests. Off by default; see below |
| coverage | `not-cran` | The same, so coverage does not under-report what those tests cover |
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

A release in flight is not drift. The process below tags after CRAN accepts,
so between `devtools::submit_cran()` and the acceptance email a package sits
at the new version with the previous tag. `drift.R` treats that as a note
when `CRAN-SUBMISSION` names the same version, and as drift otherwise —
`submit_cran()` writes that file itself, so the evidence is not hand-made.

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

## skip_on_cran, and where those tests actually run

Nowhere, by default. `skip_on_cran()` runs a test only when `NOT_CRAN` is
`"true"`, and nothing in the fleet's CI sets it: not
`r-lib/actions/check-r-package`, not `rcmdcheck`, and not `covr` either —
each checked rather than assumed. Across six packages that is 72
`skip_on_cran()` call sites whose tests have never run anywhere, and only
`guess` noticed, which is why it carries a bespoke Monte Carlo workflow.

The `not-cran` input on the check and coverage workflows turns them on. It
defaults to **false**, because switching it on can redden a repo whose
skipped tests were quietly failing — and finding that out one repo at a time,
deliberately, is the point. Turn it on per repo, read what it finds, then
leave it on.

The default is not a recommendation. A `skip_on_cran()` test that runs
nowhere is a test you are not running, and a suite that reports `PASS` while
silently skipping its only evidence of correctness is worse than no suite,
because it is trusted.

## Releasing to CRAN

The checklist is `usethis::use_release_issue()`. It is maintained by the
people who maintain the release tooling itself, so this section does not
restate it — it records only what the fleet adds or interprets. Where the two
disagree, usethis wins and this section gets a PR.

**Before submitting**, the usethis items plus fleet notes:

- `urlchecker::url_check()` — and keep the link-check workflow's weekly run
  beside it; they answer different questions (see above: R's URL database
  never sees a README badge).
- `devtools::check(remote = TRUE, manual = TRUE)`, then
  `devtools::check_win_devel()`. For anything beyond a patch,
  `rhub::rhub_setup()` + `rhub::rhub_check()` — R-hub v2 runs in the
  package's own repo, which is why `rhub.yaml` is a sanctioned extra
  workflow rather than drift.
- Reverse dependencies: `devtools::revdep()` first — most fleet packages
  have none, and the answer decides whether
  `revdepcheck::revdep_check(num_workers = 4)` is a step or a no-op. Keep
  `revdep/` out of git and out of the tarball.
- Spelling: `usethis::use_spell_check()` gives `spelling` in Suggests,
  `Language:` in DESCRIPTION, `inst/WORDLIST`, and a `tests/spelling.R`.
  That test is allowed in the suite while the lint test is banned because it
  is non-erroring by convention and WORDLIST is content, not style — a CRAN
  machine's dictionary version cannot fail your build.
- `cran-comments.md` (from `usethis::use_cran_comments()`): test
  environments, `0 errors | 0 warnings | N notes` with every NOTE explained,
  and a reverse-dependency line even when it is "there are none".

**Submission and after:**

- `devtools::submit_cran()` writes `CRAN-SUBMISSION`; it lives in the repo
  exactly as long as the submission is pending. On acceptance,
  `usethis::use_github_release()` consumes and deletes it. Neither it nor
  the legacy `CRAN-RELEASE` survives a release — `drift.R` notes stragglers.
- Tag `vX.Y.Z` (the version rule above), then
  `usethis::use_dev_version(push = TRUE)`: DESCRIPTION goes to `x.y.z.9000`
  and NEWS.md gains a `# pkgname (development version)` header. That pair is
  what the drift audit's `.9xxx` carve-out encodes; a repo that releases
  without the dev bump shows as drifted until it does one or the other.

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
