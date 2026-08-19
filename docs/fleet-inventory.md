# Fleet inventory

A census of the R packages this standard governs, taken 2026-08-19 — before
rolling the lint standard out, on the py-canon principle that migrating a
fleet twice is the expensive mistake.

**An entry in `FLEET` means monitored, not conforming.** Membership only says
the repo is ours and the drift audit watches it; conformance is what
`tools/drift.R` reports, and on census day it reported **every one of the ten
local checkouts drifted** (the seven FLEET members plus the three now recorded
as out of scope) — which is exactly why this round of the standard exists.

## Method, and how it can be wrong

- CRAN status was verified by opening each package's CRAN page and checking
  the maintainer field, not by name existence — name existence is how the
  `dann` collision below would have been missed.
- Org/repo names come from each local checkout's `origin` remote, not memory:
  two packages assumed to live in `gojiplus` actually live in `themains`, and
  `superdf` tracks `soodoku/superdf` even though a `gojiplus/superdf` also
  exists (a duplicate to resolve, noted below).
- The per-repo CI columns are `tools/drift.R` output from the census run.
  GitHub's `primaryLanguage` field was not used for anything; py-canon's
  inventory learned it lies about R repos.

## The fleet

| package | repo | CRAN | CRAN ver | local ver | latest tag | drift on census day |
|---|---|---|---|---|---|---|
| guess | finite-sample/guess | current | 0.7.0 | 0.7.0 | v0.7.0 | no lint/link shims, `.lintr` diverged, style test, extra `statistical-tests.yml` |
| bloomjoin | gojiplus/bloomjoin | no | — | 1.0.0 | none | no link/lint shims, no `.lintr` |
| tuber | gojiplus/tuber | current | 1.4.1 | 2.0.0 | v2.0.0 | no link/lint shims, `.lintr` diverged |
| tubern | gojiplus/tubern | current | 0.5.1 | 0.5.1 | v0.5.1 | no lint shim, `.lintr` diverged, style test |
| superdf | soodoku/superdf | no | — | 0.1.0 | none | no link/lint shims, no `.lintr`, no NEWS.md |
| rdomains | themains/rdomains | current | 0.5.0 | 0.5.0.9000 | v0.5.0 | no link/lint shims, `.lintr` diverged |
| virustotal | themains/virustotal | current | 0.6.0 | 0.6.0 | v0.6.0 | no link/lint shims, `.lintr` diverged, style test |

## Findings worth acting on

- **tuber ships 2.0.0 on GitHub while CRAN carries 1.4.1** — the largest
  released-but-unsubmitted gap in the fleet, and the first customer for the
  release checklist in STANDARD.md after the virustotal pilot.
- **rdomains** sits correctly at `0.5.0.9000` over `v0.5.0` — the one repo
  already following the dev-version convention the standard now audits.
- **`gojiplus/superdf` vs `soodoku/superdf`**: two repos, one package; the
  local checkout tracks `soodoku`. Pick one and archive the other.

## Out of scope, deliberately

- **aws.alexa** (`cloudyr/aws.alexa`): dead. Archived from CRAN 2026-05-14 at
  the maintainer's request, lives in an external org, edition-2 tests, CI from
  another era. Not in `FLEET`; recorded here so nobody re-discovers it.
- **dann** (`finite-sample/dann`): hands off, by decision. Also CRAN-blocked
  regardless: CRAN's `dann` 1.1.0 is Greg McMahan's Discriminant Adaptive
  Nearest Neighbor package, so this one cannot go to CRAN under its own name.
- **distortions** (`soodoku/distortions`): a research repository that happens
  to carry a DESCRIPTION, not a package to hold to a packaging standard.
- **Possibly-retired candidates** (`gojiplus/goji`, `gojiplus/recognize`,
  `appeler/namesex`, `appeler/ethnicolor`): DESCRIPTION-bearing repos that
  predate the fleet's current shape. Join `FLEET` if and when they are
  revived, not before.
