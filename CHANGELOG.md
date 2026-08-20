# Changelog

All notable changes to the standard are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Release tags are `vX.Y.Z`; the fleet-facing `v1` tag is a moving pointer
advanced by `major-tag.yml` after a release is cut, not a release of its own.

## [Unreleased]

## [1.3.2] - 2026-08-20

### Fixed

- `adopt.sh` registers `^\.lintr$` in the repo's `.Rbuildignore`. It writes
  that file, so leaving it unregistered earned a NOTE from `R CMD check`
  about a hidden file shipped in error. bloomjoin was the first adopter whose
  `.Rbuildignore` did not already happen to cover it; the other three did, so
  the gap went unseen through three adoptions.
- `drift.R`'s table no longer runs one field into the next. It prints with
  `sep = ""`, so a value at or over its column width lost its separator, and
  a `.9000` dev version -- which the standard itself prescribes between a
  release and the next submission -- is one character too wide. tuber's row
  read `2.0.0.9000v2.0.0`.

## [1.3.1] - 2026-08-19

### Fixed

- Every reusable workflow now sets `timeout-minutes`. Only the lint workflow
  had one, so a job that stalled inside `r-lib/actions` ran until GitHub's
  six-hour default: during the virustotal 0.7.0 release three of them sat in
  `setup-r` for two hours apiece. The bounds are generous (60 minutes per
  check leg, 45 for coverage and pkgdown, 15 for the link check) because they
  exist to catch a hang, not to police a slow package.
- `drift.R` no longer reports a release in flight as drift. The release
  process tags after CRAN accepts, so between `submit_cran()` and the
  acceptance email a package legitimately sits at the new version with the
  previous tag; `CRAN-SUBMISSION` naming that same version is the evidence,
  and it is written by `submit_cran()` rather than by hand. A submission
  record for an *older* version is still a stale-file note.

## [1.3.0] - 2026-08-19

### Added

- A `not-cran` input on the check and coverage workflows, off by default.
  `skip_on_cran()` runs a test only when `NOT_CRAN` is `"true"`, and nothing
  in the fleet's CI sets it — not `r-lib/actions/check-r-package`, not
  `rcmdcheck`, not `covr`, each verified rather than assumed. That is 72
  `skip_on_cran()` call sites across six packages whose tests run nowhere at
  all. Off by default because turning it on can redden a repo whose skipped
  tests were quietly failing; that is worth finding out one repo at a time.

### Fixed

- The canonical `.lintr` admits `SNAKE_CASE`, for package constants. `guess`
  keeps 33 of them in one file and could not fix it locally, since the lint
  workflow enforces the config byte-identical. Second fix the rollout has
  sent back to the standard.

## [1.2.1] - 2026-08-19

### Fixed

- The canonical `.lintr` excludes `tests/testthat/_fixtures`. `httptest2`
  records non-200 API replies as `.R` files, and linting generated code
  produced 15 unfixable lints in the virustotal pilot — the first thing the
  pilot sent back to the standard.

## [1.2.0] - 2026-08-19

### Added

- A lint standard. One canonical `.lintr` — tidyverse defaults, 100-character
  lines, `dotted.case` admitted beside `snake_case`, both deviations measured
  from the fleet — materialized into each repo by `adopt.sh` and enforced by a
  fifth reusable workflow, `reusable-lint.yml`, which first diffs the repo's
  copy against canon and then runs `lintr::lint_package()`. Style tests in the
  test suite (`test-pkg-style.R` / `expect_lint_free()`) are now drift:
  `adopt.sh` deletes them and `drift.R` fails a repo that has one.
- A "Releasing to CRAN" section in STANDARD.md. The checklist itself is
  `usethis::use_release_issue()` — usethis wins on any disagreement — and the
  section records only the fleet's additions: the link-check/urlchecker split,
  R-hub v2 via `rhub.yaml`, the revdep step, why the spelling test is allowed
  in the suite while the lint test is banned, submission-file hygiene, and the
  post-release dev-version bump the drift audit's `.9xxx` carve-out encodes.
- `FLEET` (seven `org/repo` lines; an entry means monitored, not conforming)
  and `docs/fleet-inventory.md`, a census taken before rolling the lint
  standard out: CRAN status maintainer-verified per package, per-repo drift
  from an actual `drift.R` run, and the out-of-scope list with reasons
  (aws.alexa dead, dann hands-off and CRAN-name-blocked, distortions a
  research repo). A weekly non-gating `fleet-drift` job in `ci.yml` clones
  `FLEET` and writes the audit table to the step summary.
- `drift.R` now audits everything STANDARD.md claims: the `.lintr` copy,
  LICENSE and NEWS.md presence, lint kept out of the test suite, and the
  DESCRIPTION-version-versus-tag rule (with a `.9xxx` dev-version carve-out)
  as a failure rather than a note. `rhub.yaml` becomes a sanctioned extra
  workflow; stale `CRAN-SUBMISSION`/`CRAN-RELEASE` files are noted.

- A `LICENSE` file. The standard has always required one of every package it
  governs; the repo that states the requirement now meets it.
- This changelog. Changing the fleet's mind was already a pull request to
  STANDARD.md; now each released change of mind is recorded in one place.
- r-canon validates its own changes: `ci.yml` runs actionlint and shellcheck,
  exercises `adopt.sh` and `drift.R` against a fixture package, and self-calls
  `reusable-link-check.yml`, all behind a single `gate` context (#2, #4, #5).
- Dependabot action bumps land without a human, by reference to py-canon's
  reusable auto-merge workflow (#3, #6).

## [1.1.0] - 2026-08-10

### Added

- `reusable-link-check.yml` and its `link-check.yml` shim: lychee over README,
  NEWS, DESCRIPTION, vignettes and `R/`, weekly as well as on push, because
  R's own URL database never sees image sources like README badges (#1).

### Changed

- Every `uses:` in the reusable workflows is pinned to a commit SHA with the
  version in a trailing comment, watched by Dependabot (#1).

History before 1.1.0 — the first four workflows, `adopt.sh`, `drift.R` and the
testthat-edition audit — predates this changelog and semver tags; see the git
log.
