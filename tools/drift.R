#!/usr/bin/env Rscript

# Audit a set of R package checkouts against STANDARD.md.
#
#   Rscript tools/drift.R ~/Documents/GitHub
#   Rscript tools/drift.R ~/Documents/GitHub/guess ~/Documents/GitHub/tuber
#
# Given a directory that is not itself a package, every immediate subdirectory
# containing a DESCRIPTION with a Package: field is audited. Exits 1 if any repo
# has drifted, so this can gate CI later.

canon_repo <- "gojiplus/r-canon"
pin <- "@v2"

wanted <- c(
  check = "R-CMD-check.yml",
  pkgdown = "pkgdown.yml",
  coverage = "test-coverage.yml",
  links = "link-check.yml",
  lint = "lint.yml"
)

reusable <- c(
  check = "reusable-check.yml",
  pkgdown = "reusable-pkgdown.yml",
  coverage = "reusable-coverage.yml",
  links = "reusable-link-check.yml",
  lint = "reusable-lint.yml"
)

# Workflow files beyond the shims that are not drift. rhub.yaml is written by
# rhub::rhub_setup(), and the release checklist in STANDARD.md uses R-hub v2,
# so forbidding it would ban the standard's own release process.
allowed_extra <- c("rhub.yaml", "rhub.yml")

# The canonical .lintr travels with this script: tools/drift.R sits one level
# below the repo root that holds it. Fail loudly if it cannot be found -- a
# conformance check against nothing would pass everything.
canon_lintr_path <- function() {
  arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (!length(arg)) stop("cannot locate drift.R itself; run via Rscript")
  root <- dirname(dirname(normalizePath(sub("^--file=", "", arg[1]))))
  f <- file.path(root, ".lintr")
  if (!file.exists(f)) stop("no canonical .lintr beside drift.R at ", f)
  f
}

# Trailing whitespace is not a difference of opinion about lint config.
read_clean <- function(f) sub("[ \t]+$", "", readLines(f, warn = FALSE))

lintr_status <- function(path, canon) {
  f <- file.path(path, ".lintr")
  if (!file.exists(f)) return("missing")
  if (identical(read_clean(f), read_clean(canon))) "ok" else "diverged"
}

is_pkg <- function(path) {
  d <- file.path(path, "DESCRIPTION")
  file.exists(d) && any(grepl("^Package:", readLines(d, warn = FALSE)))
}

desc_field <- function(path, field) {
  d <- file.path(path, "DESCRIPTION")
  if (!file.exists(d)) return(NA_character_)
  hit <- grep(paste0("^", field, ":"), readLines(d, warn = FALSE), value = TRUE)
  if (!length(hit)) return(NA_character_)
  trimws(sub(paste0("^", field, ":"), "", hit[1]))
}

git <- function(path, args) {
  out <- suppressWarnings(system2(
    "git", c("-C", shQuote(path), args), stdout = TRUE, stderr = FALSE
  ))
  if (!length(out)) NA_character_ else out[1]
}

# Does this repo reference the given reusable workflow, pinned to @v2?
references <- function(path, kind) {
  f <- file.path(path, ".github", "workflows", wanted[[kind]])
  if (!file.exists(f)) return("missing")
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  want <- paste0(canon_repo, "/.github/workflows/", reusable[[kind]])
  if (!grepl(want, txt, fixed = TRUE)) return("not-canon")
  if (!grepl(paste0(want, pin), txt, fixed = TRUE)) return("unpinned")
  "ok"
}

# Generated pkgdown output under version control. CI builds and publishes the
# site, so a committed docs/ is a second copy that nothing keeps current --
# tuber's was three releases behind the live site, and the live site was itself
# stale, with every pkgdown run reporting success throughout.
docs_tracked <- function(path) {
  out <- suppressWarnings(system2(
    "git", c("-C", shQuote(path), "ls-files", "--", "docs"),
    stdout = TRUE, stderr = FALSE
  ))
  length(out)
}

# CRAN answers within weeks. A record older than this is not a decision
# pending, it is a submission that never landed and was never cleaned up --
# bloomjoin's sat for eleven months, and reading it as "awaiting a decision"
# excused a real version-vs-tag drift for that whole time.
submission_max_age_days <- 60

# The version recorded in a CRAN-SUBMISSION file, or NA when there is none or
# the record is too old to be a submission still in flight.
submitted_version <- function(path) {
  f <- file.path(path, "CRAN-SUBMISSION")
  if (!file.exists(f)) return(NA_character_)
  lines <- readLines(f, warn = FALSE)

  hit <- grep("^Version:", lines, value = TRUE)
  if (!length(hit)) return(NA_character_)

  when <- grep("^Date:", lines, value = TRUE)
  if (length(when)) {
    stamp <- as.POSIXct(
      trimws(sub("^Date:", "", when[1])),
      format = "%Y-%m-%d %H:%M:%S", tz = "UTC"
    )
    age <- as.numeric(difftime(Sys.time(), stamp, units = "days"))
    if (!is.na(age) && age > submission_max_age_days) return(NA_character_)
  }

  trimws(sub("^Version:", "", hit[1]))
}

# The version rule: DESCRIPTION matches the latest v-prefixed tag, or is the
# tag's version with a .9xxx development suffix (what use_dev_version() writes
# between releases). A repo with no tags at all is pre-release, not drifted.
#
# The third case is a submission in flight. The release process tags after
# CRAN accepts, not before, so between devtools::submit_cran() and the
# acceptance email a package legitimately sits at the new version with the
# previous tag. CRAN-SUBMISSION naming that same version is the evidence, and
# it is written by submit_cran() itself rather than by hand -- but only while
# the record is recent, see submitted_version().
version_ok <- function(version, tag, submitted = NA_character_) {
  if (is.na(tag) || is.na(version)) return(TRUE)
  if (identical(paste0("v", version), tag)) return(TRUE)
  if (!is.na(submitted) && identical(submitted, version)) return(TRUE)
  startsWith(version, paste0(sub("^v", "", tag), ".9"))
}

audit <- function(path, canon_lintr) {
  wf_dir <- file.path(path, ".github", "workflows")
  present <- if (dir.exists(wf_dir)) basename(list.files(wf_dir, "\\.ya?ml$")) else character()

  version <- desc_field(path, "Version")
  tag <- git(path, c("describe", "--tags", "--abbrev=0"))

  list(
    repo = basename(path),
    version = version,
    tag = tag,
    # Not every RoxygenNote is a problem, but a 7.1.x among 7.3.x means the
    # docs were last regenerated on a different roxygen and may differ.
    roxygen = {
      r <- desc_field(path, "RoxygenNote")
      if (is.na(r)) desc_field(path, "Config/roxygen2/version") else r
    },
    check = references(path, "check"),
    pkgdown = references(path, "pkgdown"),
    coverage = references(path, "coverage"),
    links = references(path, "links"),
    lint = references(path, "lint"),
    lintr_cfg = lintr_status(path, canon_lintr),
    testthat = dir.exists(file.path(path, "tests", "testthat")),
    # STANDARD.md requires edition 3, and until now nothing checked it. A package
    # can sit on edition 2 -- still using context() and expect_that(is_a()), both
    # deprecated -- and pass this audit as "tests: yes".
    edition = desc_field(path, "Config/testthat/edition"),
    pkgdown_cfg = any(file.exists(
      file.path(path, c("_pkgdown.yml", "_pkgdown.yaml")),
      file.path(path, "pkgdown", c("_pkgdown.yml", "_pkgdown.yaml"))
    )),
    license = any(file.exists(file.path(path, c("LICENSE", "LICENSE.md")))),
    docs_tracked = docs_tracked(path),
    news = file.exists(file.path(path, "NEWS.md")),
    # Lint runs in CI, never the test suite: lintr skips expect_lint_free() on
    # CRAN, and elsewhere the test makes other machines' lintr versions into
    # style oracles for R CMD check.
    style_test = file.exists(file.path(path, "tests", "testthat", "test-pkg-style.R")),
    # A submission record for the version in DESCRIPTION is a release in
    # flight. One for an older version outlived the release it recorded.
    stale_submission = Filter(
      function(f) {
        if (!file.exists(file.path(path, f))) return(FALSE)
        !(identical(f, "CRAN-SUBMISSION") &&
            identical(submitted_version(path), version))
      },
      c("CRAN-SUBMISSION", "CRAN-RELEASE")
    ),
    in_flight = identical(submitted_version(path), version) && !is.na(version),
    version_ok = version_ok(version, tag, submitted_version(path)),
    # Files beyond the five canonical ones are what a bespoke CI system looks
    # like from the outside.
    extra = setdiff(present, c(unname(wanted), allowed_extra))
  )
}

# cat() below runs with sep = "", so a field at or over its column width would
# run into the next one. .9000 dev versions are the standard's own convention
# and overflow the version column, so keep a separating space regardless.
pad <- function(x, n) {
  out <- formatC(x, width = -n, flag = " ")
  ifelse(nchar(out) >= n, paste0(out, " "), out)
}

main <- function(args) {
  if (!length(args)) args <- "."
  canon_lintr <- canon_lintr_path()

  paths <- character()
  for (a in args) {
    a <- normalizePath(a, mustWork = FALSE)
    if (!dir.exists(a)) {
      message("no such directory: ", a)
      next
    }
    if (is_pkg(a)) {
      paths <- c(paths, a)
    } else {
      subs <- list.dirs(a, recursive = FALSE)
      paths <- c(paths, Filter(is_pkg, subs))
    }
  }
  paths <- unique(paths)

  if (!length(paths)) {
    message("no R packages found")
    return(invisible(1L))
  }

  rows <- lapply(paths, audit, canon_lintr = canon_lintr)

  mark <- function(v) if (identical(v, "ok")) "ok" else v
  yn <- function(v) if (isTRUE(v)) "yes" else "NO"
  ed <- function(has_tests, edition) {
    if (!isTRUE(has_tests)) return("NO")
    if (is.na(edition)) "ed2" else paste0("ed", trimws(edition))
  }

  cat("\n")
  cat(pad("repo", 13), pad("version", 11), pad("tag", 10), pad("roxygen", 9),
      pad("check", 10), pad("pkgdown", 10), pad("cover", 10), pad("links", 10),
      pad("lint", 10), pad(".lintr", 9), pad("tests", 6), pad("site", 6),
      "extra\n", sep = "")
  cat(strrep("-", 132), "\n", sep = "")

  drifted <- character()
  for (r in rows) {
    shims <- c(r$check, r$pkgdown, r$coverage, r$links, r$lint)
    bad <- !all(shims == "ok") ||
      !identical(r$lintr_cfg, "ok") ||
      !r$testthat || !r$pkgdown_cfg || length(r$extra) > 0 ||
      !identical(ed(r$testthat, r$edition), "ed3") ||
      !r$license || !r$news || r$style_test || !r$version_ok ||
      r$docs_tracked > 0
    if (bad) drifted <- c(drifted, r$repo)

    cat(
      pad(r$repo, 13),
      pad(ifelse(is.na(r$version), "-", r$version), 11),
      pad(ifelse(is.na(r$tag), "-", r$tag), 10),
      pad(ifelse(is.na(r$roxygen), "-", r$roxygen), 9),
      pad(mark(r$check), 10),
      pad(mark(r$pkgdown), 10),
      pad(mark(r$coverage), 10),
      pad(mark(r$links), 10),
      pad(mark(r$lint), 10),
      pad(mark(r$lintr_cfg), 9),
      pad(ed(r$testthat, r$edition), 6),
      pad(yn(r$pkgdown_cfg), 6),
      if (length(r$extra)) paste(r$extra, collapse = " ") else "-",
      "\n",
      sep = ""
    )

    note <- function(...) cat(pad("", 13), ..., "\n", sep = "")
    if (!r$version_ok) {
      note("DRIFT: DESCRIPTION ", r$version, " but latest tag ", r$tag,
           " (release the version or bump to a .9xxx dev version)")
    }
    if (!r$license) note("DRIFT: no LICENSE file")
    if (!r$news) note("DRIFT: no NEWS.md")
    if (r$docs_tracked > 0) {
      note("DRIFT: ", r$docs_tracked, " generated pkgdown file(s) committed under docs/",
           " -- CI builds and publishes the site; gitignore docs/")
    }
    if (r$style_test) {
      note("DRIFT: tests/testthat/test-pkg-style.R -- lint belongs in CI, not the test suite")
    }
    if (isTRUE(r$in_flight)) {
      note("note: ", r$version, " submitted to CRAN and awaiting a decision",
           " -- tag it once accepted")
    }
    if (length(r$stale_submission)) {
      note("note: ", paste(r$stale_submission, collapse = " and "),
           " present -- submission records should not outlive the release")
    }
  }

  cat("\n")
  if (length(drifted)) {
    cat(length(drifted), " of ", length(rows), " drifted: ",
        paste(drifted, collapse = ", "), "\n\n", sep = "")
    invisible(1L)
  } else {
    cat("all ", length(rows), " repos on the standard\n\n", sep = "")
    invisible(0L)
  }
}

if (!interactive()) {
  quit(status = main(commandArgs(trailingOnly = TRUE)))
}
