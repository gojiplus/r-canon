#!/usr/bin/env Rscript

# Audit a set of R package checkouts against STANDARD.md.
#
#   Rscript tools/drift.R ~/Documents/GitHub
#   Rscript tools/drift.R ~/Documents/GitHub/guess ~/Documents/GitHub/tuber
#
# Given a directory that is not itself a package, every immediate subdirectory
# containing a DESCRIPTION with a Package: field is audited. Exits 1 if any repo
# has drifted, so this can gate CI later.

CANON <- "gojiplus/r-canon"
PIN <- "@v1"

WANTED <- c(
  check = "R-CMD-check.yml",
  pkgdown = "pkgdown.yml",
  coverage = "test-coverage.yml"
)

REUSABLE <- c(
  check = "reusable-check.yml",
  pkgdown = "reusable-pkgdown.yml",
  coverage = "reusable-coverage.yml"
)

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

# Does this repo reference the given reusable workflow, pinned to @v1?
references <- function(path, kind) {
  f <- file.path(path, ".github", "workflows", WANTED[[kind]])
  if (!file.exists(f)) return("missing")
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  want <- paste0(CANON, "/.github/workflows/", REUSABLE[[kind]])
  if (!grepl(want, txt, fixed = TRUE)) return("not-canon")
  if (!grepl(paste0(want, PIN), txt, fixed = TRUE)) return("unpinned")
  "ok"
}

audit <- function(path) {
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
    testthat = dir.exists(file.path(path, "tests", "testthat")),
    pkgdown_cfg = any(file.exists(
      file.path(path, c("_pkgdown.yml", "_pkgdown.yaml")),
      file.path(path, "pkgdown", c("_pkgdown.yml", "_pkgdown.yaml"))
    )),
    # Files beyond the three canonical ones are what a bespoke CI system looks
    # like from the outside.
    extra = setdiff(present, unname(WANTED))
  )
}

pad <- function(x, n) formatC(x, width = -n, flag = " ")

main <- function(args) {
  if (!length(args)) args <- "."

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

  rows <- lapply(paths, audit)

  mark <- function(v) if (identical(v, "ok")) "ok" else v
  yn <- function(v) if (isTRUE(v)) "yes" else "NO"

  cat("\n")
  cat(pad("repo", 13), pad("version", 9), pad("tag", 10), pad("roxygen", 9),
      pad("check", 10), pad("pkgdown", 10), pad("cover", 10),
      pad("tests", 6), pad("site", 6), "extra\n", sep = "")
  cat(strrep("-", 108), "\n", sep = "")

  drifted <- character()
  for (r in rows) {
    bad <- !all(c(r$check, r$pkgdown, r$coverage) == "ok") ||
      !r$testthat || !r$pkgdown_cfg || length(r$extra) > 0
    if (bad) drifted <- c(drifted, r$repo)

    cat(
      pad(r$repo, 13),
      pad(ifelse(is.na(r$version), "-", r$version), 9),
      pad(ifelse(is.na(r$tag), "-", r$tag), 10),
      pad(ifelse(is.na(r$roxygen), "-", r$roxygen), 9),
      pad(mark(r$check), 10),
      pad(mark(r$pkgdown), 10),
      pad(mark(r$coverage), 10),
      pad(yn(r$testthat), 6),
      pad(yn(r$pkgdown_cfg), 6),
      if (length(r$extra)) paste(r$extra, collapse = " ") else "-",
      "\n",
      sep = ""
    )

    # A version that does not match the latest tag is worth seeing but is not
    # drift from the standard -- it usually just means unreleased work.
    if (!is.na(r$version) && !is.na(r$tag) &&
        !identical(paste0("v", r$version), r$tag)) {
      cat(pad("", 13), "note: DESCRIPTION ", r$version,
          " but latest tag ", r$tag, "\n", sep = "")
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
