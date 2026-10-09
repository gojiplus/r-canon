gate_script <- function() {
  lines <- readLines(file.path("..", "..", ".github", "workflows", "major-tag.yml"))
  start <- which(lines == "      - name: Require successful CI for the target commit")
  stopifnot(length(start) == 1L)
  rest <- lines[seq.int(start + 1L, length(lines))]
  end <- which(grepl("^      - name:", rest))[1]
  block <- rest[seq_len(end - 1L)]
  block <- block[seq.int(which(block == "        run: |") + 1L, length(block))]
  sub("^          ", "", block)
}

testthat::test_that("promotion requires successful CI and fails on API errors", {
  dir <- tempfile()
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  gh <- file.path(dir, "gh")
  writeLines(c(
    "#!/bin/sh",
    'printf "%s\\n" "$@" > "$ARGUMENTS"',
    'printf "%s\\n" "$CI_CONCLUSION"',
    'exit "$GH_EXIT"'
  ), gh)
  Sys.chmod(gh, "0755")
  script <- file.path(dir, "gate.sh")
  writeLines(gate_script(), script)
  vars <- c("PATH", "ARGUMENTS", "CI_CONCLUSION", "GH_EXIT", "TARGET", "DEFAULT_BRANCH")
  before <- Sys.getenv(vars, unset = NA_character_)
  on.exit({
    for (name in vars) {
      if (is.na(before[[name]])) Sys.unsetenv(name)
      else do.call(Sys.setenv, setNames(list(before[[name]]), name))
    }
  }, add = TRUE)
  Sys.setenv(
    PATH = paste(dir, Sys.getenv("PATH"), sep = .Platform$path.sep),
    ARGUMENTS = file.path(dir, "arguments"), TARGET = strrep("a", 40),
    DEFAULT_BRANCH = "main", GH_EXIT = "0"
  )
  for (conclusion in c("failure", "", "cancelled", "null", "skipped", "success")) {
    Sys.setenv(CI_CONCLUSION = conclusion)
    status <- system2("bash", shQuote(script), stdout = FALSE, stderr = FALSE)
    testthat::expect_identical(status, if (conclusion == "success") 0L else 1L)
  }
  args <- readLines(file.path(dir, "arguments"))
  testthat::expect_identical(args[match("--commit", args) + 1L], strrep("a", 40))
  testthat::expect_identical(args[match("--branch", args) + 1L], "main")
  testthat::expect_identical(args[match("--workflow", args) + 1L], "ci.yml")
  testthat::expect_false("--status" %in% args)
  Sys.setenv(GH_EXIT = "1", CI_CONCLUSION = "success")
  testthat::expect_identical(
    system2("bash", shQuote(script), stdout = FALSE, stderr = FALSE), 1L
  )
})
