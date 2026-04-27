current_file <- function() {
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    if (!is.null(frames[[i]]$ofile)) {
      return(normalizePath(frames[[i]]$ofile))
    }
  }
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[[1]])))
  }
  normalizePath("app.R", mustWork = FALSE)
}

example_dir <- dirname(current_file())
source(file.path(example_dir, "apps.R"), local = TRUE)

use_case <- Sys.getenv("SHINYMCP_USE_CASE", "revenue")
app <- shinymcp_use_case(use_case)

serve(app)
