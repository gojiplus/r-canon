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
| CI | References the three reusable workflows below, pinned to `@v1` |
| Workflow filenames | `R-CMD-check.yml`, `pkgdown.yml`, `test-coverage.yml` — exactly these |
| Checks on | Ubuntu release/devel/oldrel-1, macOS release, Windows release |
| Check bar | `R CMD check --as-cran` clean; warnings fail the build |
| Tests | `testthat`, edition 3, under `tests/testthat/` |
| Docs | roxygen2, and a `pkgdown` site deployed to `gh-pages` |
| Version | Semantic, in `DESCRIPTION`, matching a `v`-prefixed git tag |
| License | Declared in `DESCRIPTION` with a `LICENSE` file |
| News | `NEWS.md`, newest first, one section per released version |

## Consuming it

Three files, six lines each. Everything else lives here.

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
    uses: gojiplus/r-canon/.github/workflows/reusable-pkgdown.yml@v1
```

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

## Inputs, and why there are so few

The check matrix is **not** an input. It is the five configurations CRAN runs,
and a package needing a different set needs a conversation rather than a knob —
a standard you can configure your way out of is not a standard. Drift re-enters
through options.

The inputs that do exist cover the places packages legitimately differ:

| workflow | input | when to set it |
|---|---|---|
| check | `build-args` | A package with no vignettes can drop `--compact-vignettes` and its ghostscript dependency |
| check | `error-on` | Temporarily loosening to `"error"` while a warning is fixed. Say in a comment when it goes back |
| check | `extra-packages` | A package whose checks need something beyond `rcmdcheck` |
| pkgdown | `extra-packages` | Same, for the site build |

## Versioning

Tags version the workflows together. Repos reference the moving major tag `v1`,
so a fix here reaches every repo on its next run. Breaking changes to the
standard — anything that would make a currently-green repo fail — bump to `v2`,
and repos move over deliberately.

## Drift

`tools/drift.R` audits a set of checkouts against this file and exits non-zero
if any has drifted:

```bash
Rscript tools/drift.R ~/Documents/GitHub
```

It reports whether each repo references `@v1`, uses the canonical filenames, has
`testthat` and `pkgdown`, and whether its `DESCRIPTION` version matches its
latest tag.

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
  would just be drift again.
