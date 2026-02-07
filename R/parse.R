# Parse Shiny apps into intermediate representation

# Known Shiny input function names
shiny_input_fns <- c(
  "selectInput",
  "selectizeInput",
  "textInput",
  "textAreaInput",
  "numericInput",
  "checkboxInput",
  "checkboxGroupInput",
  "sliderInput",
  "radioButtons",
  "actionButton",
  "actionLink",
  "dateInput",
  "dateRangeInput",
  "fileInput",
  "passwordInput"
)

# Known Shiny output function names
shiny_output_fns <- c(
  "plotOutput",
  "textOutput",
  "verbatimTextOutput",
  "tableOutput",
  "dataTableOutput",
  "htmlOutput",
  "uiOutput",
  "imageOutput",
  "downloadButton"
)

#' Parse a Shiny app into intermediate representation
#'
#' Reads a Shiny app's R source files and extracts a structured representation
#' of UI inputs, outputs, and server logic.
#'
#' @param path Path to a Shiny app directory (containing app.R or ui.R/server.R)
#' @return A `ShinyAppIR` list with components: `inputs`, `outputs`, `server_body`,
#'   `reactives`, `observers`, `complexity`
#' @export
parse_shiny_app <- function(path) {
  path <- normalizePath(path, mustWork = TRUE)

  # Determine app structure
  app_file <- file.path(path, "app.R")
  ui_file <- file.path(path, "ui.R")
  server_file <- file.path(path, "server.R")

  if (file.exists(app_file)) {
    exprs <- parse(app_file)
  } else if (file.exists(ui_file) && file.exists(server_file)) {
    exprs <- c(parse(ui_file), parse(server_file))
  } else {
    shinymcp_error_parse("Could not find app.R or ui.R/server.R", path = path)
  }

  # Walk AST to extract components
  inputs <- extract_inputs(exprs)
  outputs <- extract_outputs(exprs)
  server_body <- extract_server_body(exprs)
  reactives <- extract_reactives(server_body)
  observers <- extract_observers(server_body)
  input_refs <- extract_input_refs(server_body)

  complexity <- classify_complexity(inputs, outputs, reactives, observers)

  structure(
    list(
      path = path,
      inputs = inputs,
      outputs = outputs,
      server_body = server_body,
      reactives = reactives,
      observers = observers,
      input_refs = input_refs,
      complexity = complexity
    ),
    class = "ShinyAppIR"
  )
}

#' Extract Shiny input definitions from parsed expressions
#' @param exprs Parsed R expressions
#' @return List of input definitions (id, type, label, args)
#' @noRd
extract_inputs <- function(exprs) {
  inputs <- list()
  walk_exprs(exprs, function(expr) {
    if (is_input_call(expr)) {
      input <- parse_input_call(expr)
      if (!is.null(input)) {
        inputs[[length(inputs) + 1L]] <<- input
      }
    }
  })
  inputs
}

#' Extract Shiny output definitions from parsed expressions
#' @param exprs Parsed R expressions
#' @return List of output definitions (id, type)
#' @noRd
extract_outputs <- function(exprs) {
  outputs <- list()
  walk_exprs(exprs, function(expr) {
    if (is_output_call(expr)) {
      output <- parse_output_call(expr)
      if (!is.null(output)) {
        outputs[[length(outputs) + 1L]] <<- output
      }
    }
  })
  outputs
}

#' Extract the server function body from parsed expressions
#'
#' Finds the server function in shinyApp(), shinyServer(), or
#' a `server <- function(...)` assignment. Extracts the body expression
#' directly from the AST without evaluating code.
#'
#' @param exprs Parsed R expressions
#' @return The body expression of the server function, or NULL
#' @noRd
extract_server_body <- function(exprs) {
  for (expr in exprs) {
    if (!is.call(expr)) {
      next
    }
    fn_name <- call_name(expr)

    # shinyApp(ui = ..., server = function(input, output, session) { ... })
    if (identical(fn_name, "shinyApp")) {
      server_arg <- find_named_arg(expr, "server")
      if (is.null(server_arg) && length(expr) >= 3) {
        # Positional: shinyApp(ui, server)
        server_arg <- expr[[3]]
      }
      body <- extract_function_body(server_arg)
      if (!is.null(body)) return(body)
    }

    # server <- function(input, output, session) { ... }
    if (fn_name %in% c("<-", "=")) {
      lhs <- expr[[2]]
      rhs <- expr[[3]]
      if (is.name(lhs) && identical(as.character(lhs), "server")) {
        body <- extract_function_body(rhs)
        if (!is.null(body)) return(body)
      }
    }

    # shinyServer(function(input, output, session) { ... })
    if (identical(fn_name, "shinyServer") && length(expr) >= 2) {
      body <- extract_function_body(expr[[2]])
      if (!is.null(body)) return(body)
    }
  }
  NULL
}

#' Extract the body from a function expression without evaluating it
#'
#' Given a `function(x, y) { body }` expression, returns the body
#' portion directly from the parse tree.
#'
#' @param expr An R expression
#' @return The body expression, or NULL if not a function expression
#' @noRd
extract_function_body <- function(expr) {
  if (is.null(expr)) {
    return(NULL)
  }
  # A function expression like `function(a, b) { ... }` is a call with:
  #   expr[[1]] = `function`
  #   expr[[2]] = pairlist of formals
  #   expr[[3]] = body
  if (
    is.call(expr) &&
      identical(expr[[1]], as.name("function")) &&
      length(expr) >= 3
  ) {
    return(expr[[3]])
  }
  NULL
}

#' Extract reactive expressions from server body
#' @param server_body Server function body expression
#' @return List of reactive definitions (name, body_expr, input_deps)
#' @noRd
extract_reactives <- function(server_body) {
  if (is.null(server_body)) {
    return(list())
  }

  reactives <- list()

  # Walk top-level statements looking for assignment to reactive()
  stmts <- if (
    is.call(server_body) && identical(server_body[[1]], as.name("{"))
  ) {
    as.list(server_body[-1])
  } else {
    list(server_body)
  }

  for (stmt in stmts) {
    if (!is.call(stmt)) {
      next
    }
    fn_name <- call_name(stmt)
    if (fn_name %in% c("<-", "=")) {
      lhs <- stmt[[2]]
      rhs <- stmt[[3]]
      if (
        is.name(lhs) && is.call(rhs) && identical(call_name(rhs), "reactive")
      ) {
        reactive_body <- if (length(rhs) >= 2) rhs[[2]] else NULL
        input_deps <- if (!is.null(reactive_body)) {
          find_input_refs_in(reactive_body)
        } else {
          character()
        }
        reactives[[length(reactives) + 1L]] <- list(
          name = as.character(lhs),
          body_expr = reactive_body,
          input_deps = input_deps
        )
      }
    }
  }

  reactives
}

#' Extract observers from server body
#' @param server_body Server function body expression
#' @return List of observer definitions
#' @noRd
extract_observers <- function(server_body) {
  if (is.null(server_body)) {
    return(list())
  }

  observers <- list()
  stmts <- if (
    is.call(server_body) && identical(server_body[[1]], as.name("{"))
  ) {
    as.list(server_body[-1])
  } else {
    list(server_body)
  }

  for (stmt in stmts) {
    if (!is.call(stmt)) {
      next
    }

    # Check direct observer calls and assignment-wrapped observer calls
    observer <- try_parse_observer(stmt)
    if (!is.null(observer)) {
      observers[[length(observers) + 1L]] <- observer
      next
    }

    # Check if wrapped in assignment: x <- observeEvent(...)
    fn_name <- call_name(stmt)
    if (fn_name %in% c("<-", "=") && is.call(stmt[[3]])) {
      observer <- try_parse_observer(stmt[[3]])
      if (!is.null(observer)) {
        observers[[length(observers) + 1L]] <- observer
      }
    }
  }

  observers
}

#' Try to parse an expression as an observer call
#' @param expr An R expression
#' @return Observer list or NULL
#' @noRd
try_parse_observer <- function(expr) {
  if (!is.call(expr)) {
    return(NULL)
  }
  fn_name <- call_name(expr)

  if (identical(fn_name, "observeEvent") && length(expr) >= 3) {
    event_expr <- expr[[2]]
    handler_expr <- expr[[3]]
    return(list(
      type = "observeEvent",
      event_expr = event_expr,
      handler_expr = handler_expr,
      input_deps = find_input_refs_in(event_expr)
    ))
  }

  if (identical(fn_name, "observe") && length(expr) >= 2) {
    body_expr <- expr[[2]]
    return(list(
      type = "observe",
      body_expr = body_expr,
      input_deps = find_input_refs_in(body_expr)
    ))
  }

  NULL
}

#' Extract all input$name references from server body
#' @param server_body Server function body expression
#' @return Character vector of input names referenced
#' @noRd
extract_input_refs <- function(server_body) {
  if (is.null(server_body)) {
    return(character())
  }
  unique(find_input_refs_in(server_body))
}

#' Classify app complexity
#' @param inputs List of inputs
#' @param outputs List of outputs
#' @param reactives List of reactives
#' @param observers List of observers
#' @return "simple", "medium", or "complex"
#' @noRd
classify_complexity <- function(inputs, outputs, reactives, observers) {
  n_inputs <- length(inputs)
  n_reactives <- length(reactives)
  n_observers <- length(observers)

  if (n_inputs <= 3 && n_reactives == 0 && n_observers == 0) {
    "simple"
  } else if (n_inputs <= 8 && n_reactives <= 3) {
    "medium"
  } else {
    "complex"
  }
}

#' Check if an expression is a Shiny input function call
#' @param expr An R expression
#' @return Logical
#' @noRd
is_input_call <- function(expr) {
  if (!is.call(expr)) {
    return(FALSE)
  }
  fn_name <- call_name(expr)
  fn_name %in% shiny_input_fns
}

#' Check if an expression is a Shiny output function call
#' @param expr An R expression
#' @return Logical
#' @noRd
is_output_call <- function(expr) {
  if (!is.call(expr)) {
    return(FALSE)
  }
  fn_name <- call_name(expr)
  fn_name %in% shiny_output_fns
}

#' Parse a Shiny input call into structured data
#' @param expr A call expression that is a Shiny input
#' @return List with id, type, label, args; or NULL
#' @noRd
parse_input_call <- function(expr) {
  fn_name <- call_name(expr)
  args <- as.list(match.call(
    definition = get_shiny_fn_formals(fn_name),
    call = expr
  ))[-1]

  id <- try_deparse_arg(args[["inputId"]] %||% args[[1]])
  label <- try_deparse_arg(args[["label"]] %||% args[[2]])

  if (is.null(id)) {
    return(NULL)
  }

  # Map Shiny function name to input type
  type <- sub("Input$", "", fn_name)
  type <- sub("Buttons$", "", type)

  list(
    id = id,
    type = type,
    label = label %||% id,
    fn_name = fn_name,
    args = args
  )
}

#' Parse a Shiny output call into structured data
#' @param expr A call expression that is a Shiny output
#' @return List with id, type; or NULL
#' @noRd
parse_output_call <- function(expr) {
  fn_name <- call_name(expr)
  args <- as.list(expr)[-1]

  id <- try_deparse_arg(args[["outputId"]] %||% args[[1]])
  if (is.null(id)) {
    return(NULL)
  }

  type <- sub("Output$", "", fn_name)
  type <- sub("Button$", "", type)

  list(
    id = id,
    type = type
  )
}

# ---- Internal AST utilities ----

#' Get the function name from a call expression
#' @param expr A call expression
#' @return Character function name, or ""
#' @noRd
call_name <- function(expr) {
  if (!is.call(expr)) {
    return("")
  }
  fn <- expr[[1]]
  if (is.name(fn)) {
    as.character(fn)
  } else if (is.call(fn) && identical(fn[[1]], as.name("::"))) {
    # pkg::fn case
    as.character(fn[[3]])
  } else {
    ""
  }
}

#' Walk all sub-expressions recursively, calling fn on each
#' @param exprs Expressions to walk
#' @param fn Callback function
#' @noRd
walk_exprs <- function(exprs, fn) {
  if (is.null(exprs)) {
    return()
  }
  for (expr in as.list(exprs)) {
    if (is.null(expr)) {
      next
    }
    fn(expr)
    if (is.call(expr) || is.recursive(expr)) {
      walk_exprs(as.list(expr)[-1], fn)
    }
  }
}

#' Find all input$name references in an expression
#' @param expr An R expression
#' @return Character vector of input names
#' @noRd
find_input_refs_in <- function(expr) {
  refs <- character()
  walk_exprs(list(expr), function(e) {
    if (is.call(e) && identical(call_name(e), "$")) {
      if (is.name(e[[2]]) && identical(as.character(e[[2]]), "input")) {
        if (is.name(e[[3]])) {
          refs[length(refs) + 1L] <<- as.character(e[[3]])
        }
      }
    }
    # Also catch input[["name"]] pattern
    if (is.call(e) && identical(call_name(e), "[[")) {
      if (is.name(e[[2]]) && identical(as.character(e[[2]]), "input")) {
        val <- try_deparse_arg(e[[3]])
        if (is.character(val)) {
          refs[length(refs) + 1L] <<- val
        }
      }
    }
  })
  unique(refs)
}

#' Find a named argument in a call
#' @param call_expr A call expression
#' @param name Name to find
#' @return The argument value, or NULL
#' @noRd
find_named_arg <- function(call_expr, name) {
  args <- as.list(call_expr)[-1]
  nms <- names(args)
  if (is.null(nms)) {
    return(NULL)
  }
  idx <- match(name, nms)
  if (is.na(idx)) NULL else args[[idx]]
}

#' Try to extract a literal value from an argument expression
#'
#' Works for string literals, numeric literals, and logical literals
#' without evaluating arbitrary code.
#'
#' @param x Expression to inspect
#' @return The literal value if extractable, NULL otherwise
#' @noRd
try_deparse_arg <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (is.character(x)) {
    return(x)
  }
  if (is.numeric(x)) {
    return(x)
  }
  if (is.logical(x)) {
    return(x)
  }
  if (is.name(x)) {
    return(NULL)
  } # Can't resolve variable references
  # For simple literal expressions, deparse safely
  NULL
}

#' Get formals for a Shiny input/output function
#'
#' Returns a minimal function with expected formals so match.call() works.
#' @param fn_name The Shiny function name
#' @return A function with the appropriate formals
#' @noRd
get_shiny_fn_formals <- function(fn_name) {
  # Standard formals for common Shiny input functions
  formals_map <- list(
    selectInput = function(
      inputId,
      label,
      choices,
      selected = NULL,
      multiple = FALSE,
      ...
    ) {
      NULL
    },
    selectizeInput = function(
      inputId,
      label,
      choices,
      selected = NULL,
      multiple = FALSE,
      ...
    ) {
      NULL
    },
    textInput = function(inputId, label, value = "", placeholder = NULL, ...) {
      NULL
    },
    textAreaInput = function(
      inputId,
      label,
      value = "",
      placeholder = NULL,
      ...
    ) {
      NULL
    },
    numericInput = function(
      inputId,
      label,
      value,
      min = NA,
      max = NA,
      step = NA,
      ...
    ) {
      NULL
    },
    checkboxInput = function(inputId, label, value = FALSE, ...) NULL,
    checkboxGroupInput = function(
      inputId,
      label,
      choices,
      selected = NULL,
      ...
    ) {
      NULL
    },
    sliderInput = function(inputId, label, min, max, value, step = NULL, ...) {
      NULL
    },
    radioButtons = function(inputId, label, choices, selected = NULL, ...) NULL,
    actionButton = function(inputId, label, ...) NULL,
    actionLink = function(inputId, label, ...) NULL,
    dateInput = function(inputId, label, value = NULL, ...) NULL,
    dateRangeInput = function(inputId, label, start = NULL, end = NULL, ...) {
      NULL
    },
    fileInput = function(inputId, label, multiple = FALSE, ...) NULL,
    passwordInput = function(inputId, label, value = "", ...) NULL,
    plotOutput = function(outputId, width = "100%", height = "400px", ...) NULL,
    textOutput = function(outputId, ...) NULL,
    verbatimTextOutput = function(outputId, ...) NULL,
    tableOutput = function(outputId, ...) NULL,
    dataTableOutput = function(outputId, ...) NULL,
    htmlOutput = function(outputId, ...) NULL,
    uiOutput = function(outputId, ...) NULL,
    imageOutput = function(outputId, ...) NULL,
    downloadButton = function(outputId, label = "Download", ...) NULL
  )

  formals_map[[fn_name]] %||% function(...) NULL
}

#' Print method for ShinyAppIR
#' @param x A ShinyAppIR object
#' @param ... Ignored
#' @export
print.ShinyAppIR <- function(x, ...) {
  cli::cli_h1("Shiny App IR")
  cli::cli_text("Path: {.path {x$path}}")
  cli::cli_text("Inputs: {length(x$inputs)}")
  cli::cli_text("Outputs: {length(x$outputs)}")
  cli::cli_text("Reactives: {length(x$reactives)}")
  cli::cli_text("Observers: {length(x$observers)}")
  cli::cli_text("Complexity: {x$complexity}")
  if (length(x$input_refs) > 0) {
    cli::cli_text("Input refs: {paste(x$input_refs, collapse = ', ')}")
  }
  invisible(x)
}
