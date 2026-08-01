# r-canon

One versioned standard for the fleet's R packages, and the reusable workflows
that keep them on it without copy-paste.

**The standard:** [STANDARD.md](STANDARD.md) — CRAN-shaped `R CMD check` across
five platforms, testthat, roxygen2, pkgdown, semantic versions matching tags.
Changing the fleet's mind is a pull request to that file.

**The machinery:** three reusable workflows. Repos reference them in six lines;
all the logic lives here, so a fix propagates on the next run.

| Workflow | What it does |
|---|---|
| `reusable-check.yml` | `R CMD check` on Ubuntu release/devel/oldrel-1, macOS, Windows |
| `reusable-pkgdown.yml` | Builds the site on every push and PR; deploys only from the default branch or a tag |
| `reusable-coverage.yml` | Runs `covr`; uploads to Codecov when a token exists, keeps an artifact when it doesn't |

## Adopting a repo

Drop in three files, delete whatever was there before:

```yaml
# .github/workflows/R-CMD-check.yml
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

The other two are in [STANDARD.md](STANDARD.md).

## Checking for drift

```bash
Rscript tools/drift.R ~/Documents/GitHub
```

Audits every R package under a directory and exits non-zero if any has drifted —
wrong workflow filenames, unpinned or missing references, no testthat, no
pkgdown config, or leftover bespoke workflows.

## Why this is smaller than py-canon

[py-canon](https://github.com/gojiplus/py-canon) carries a copier template,
reusable workflows, shared Sphinx config, and a conformance CLI, because Python
had no shared answer for any of it. R does. `usethis` and `rcompendium` scaffold
packages; `r-lib/actions` runs the CI steps; `pkgdown` builds sites; `lintr` and
`goodpractice` check style; `R CMD check --as-cran` is the bar.

The one thing R has no answer for is keeping a *set* of repos on one standard,
because `r-lib/actions` ships example workflows to **copy** rather than
workflows to **reference**. Copies drift — across nine repos here there were
five different filenames for the same job, one repo with no CI at all, and one
running six bespoke workflows. That gap is all this repo fills.

## Versioning

Tags version the workflows together. Repos reference the moving major tag `v1`.
Breaking changes — anything that would make a currently-green repo fail — bump
to `v2`.
