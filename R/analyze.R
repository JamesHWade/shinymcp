# Analyze reactive graph from parsed Shiny app

#' Analyze reactive graph from parsed Shiny app
#'
#' Builds a dependency graph from inputs through reactives to outputs,
#' and groups connected components into tool groups.
#'
#' @param ir A `ShinyAppIR` object from [parse_shiny_app()]
#' @return A `ReactiveAnalysis` list with components: `graph`, `tool_groups`, `warnings`
#' @export
analyze_reactive_graph <- function(ir) {
  if (!inherits(ir, "ShinyAppIR")) {
    shinymcp_error_analysis("Expected a ShinyAppIR object")
  }

  # Build adjacency: input -> reactive -> output
  graph <- build_dependency_graph(ir)

  # Find connected components
  components <- find_connected_components(graph)

  # Map each component to a tool group
  tool_groups <- lapply(components, function(comp) {
    make_tool_group(comp, ir)
  })

  warnings <- check_unresolvable_patterns(ir)

  structure(
    list(
      graph = graph,
      tool_groups = tool_groups,
      warnings = warnings
    ),
    class = "ReactiveAnalysis"
  )
}

#' Build dependency graph from IR
#'
#' Creates an adjacency list mapping nodes (inputs, reactives, outputs) to
#' their connections. Edges flow from inputs -> reactives -> outputs.
#'
#' @param ir A ShinyAppIR object
#' @return A list with `nodes` and `edges`
#' @noRd
build_dependency_graph <- function(ir) {
  nodes <- list()
  edges <- list()

  # Add input nodes
  for (inp in ir$inputs) {
    nodes[[paste0("input:", inp$id)]] <- list(
      type = "input",
      id = inp$id,
      data = inp
    )
  }

  # Add output nodes and find their input dependencies from render expressions
  output_deps <- find_output_dependencies(ir$server_body, ir$reactives)
  for (out in ir$outputs) {
    node_id <- paste0("output:", out$id)
    nodes[[node_id]] <- list(
      type = "output",
      id = out$id,
      data = out
    )

    # Connect inputs to this output
    deps <- output_deps[[out$id]]
    if (!is.null(deps)) {
      for (dep in deps$input_deps) {
        edge_id <- paste0("input:", dep, "->output:", out$id)
        edges[[edge_id]] <- list(
          from = paste0("input:", dep),
          to = node_id
        )
      }
      for (dep in deps$reactive_deps) {
        edge_id <- paste0("reactive:", dep, "->output:", out$id)
        edges[[edge_id]] <- list(
          from = paste0("reactive:", dep),
          to = node_id
        )
      }
    }
  }

  # Add reactive nodes and their edges
  for (react in ir$reactives) {
    node_id <- paste0("reactive:", react$name)
    nodes[[node_id]] <- list(
      type = "reactive",
      id = react$name,
      data = react
    )
    # Reactives depend on inputs
    for (dep in react$input_deps) {
      edge_id <- paste0("input:", dep, "->reactive:", react$name)
      edges[[edge_id]] <- list(
        from = paste0("input:", dep),
        to = node_id
      )
    }
    # Reactives depend on other reactives
    for (dep in react$reactive_deps) {
      edge_id <- paste0("reactive:", dep, "->reactive:", react$name)
      edges[[edge_id]] <- list(
        from = paste0("reactive:", dep),
        to = node_id
      )
    }
  }

  list(nodes = nodes, edges = edges)
}

#' Find which inputs each output depends on
#'
#' Scans render* expressions in the server body to find input$xxx references.
#' Transitively expands reactive dependencies to capture the full chain.
#'
#' @param server_body Server function body expression
#' @param reactives List of reactive definitions
#' @return Named list mapping output IDs to their dependencies
#' @noRd
find_output_dependencies <- function(server_body, reactives) {
  if (is.null(server_body)) {
    return(list())
  }

  deps <- list()
  reactive_names <- vapply(reactives, function(r) r$name, character(1))

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

    # output$name <- renderXxx({ ... })
    fn_name <- call_name(stmt)
    if (fn_name %in% c("<-", "=")) {
      lhs <- stmt[[2]]
      rhs <- stmt[[3]]

      # Check for output$name pattern
      if (is.call(lhs) && identical(call_name(lhs), "$")) {
        if (is.name(lhs[[2]]) && identical(as.character(lhs[[2]]), "output")) {
          output_id <- as.character(lhs[[3]])
          input_refs <- find_input_refs_in(rhs)

          # Also find reactive references: calls to reactive_name()
          reactive_refs <- character()
          walk_exprs(list(rhs), function(e) {
            if (is.call(e) && is.name(e[[1]])) {
              fn <- as.character(e[[1]])
              if (fn %in% reactive_names) {
                reactive_refs[length(reactive_refs) + 1L] <<- fn
              }
            }
          })

          # Transitively expand reactive deps to capture the full chain
          all_reactive_refs <- expand_reactive_deps(
            unique(reactive_refs),
            reactives
          )
          expanded_input_refs <- input_refs
          for (rname in all_reactive_refs) {
            ridx <- match(rname, reactive_names)
            if (!is.na(ridx)) {
              expanded_input_refs <- c(
                expanded_input_refs,
                reactives[[ridx]]$input_deps
              )
            }
          }

          deps[[output_id]] <- list(
            input_deps = unique(expanded_input_refs),
            reactive_deps = all_reactive_refs,
            render_expr = rhs
          )
        }
      }
    }
  }

  deps
}

#' Transitively expand reactive dependencies
#'
#' Given a set of reactive names, follows `reactive_deps` chains to collect
#' the full transitive closure of all upstream reactives.
#'
#' @param initial Character vector of reactive names to start from
#' @param reactives List of reactive definitions from the IR
#' @return Character vector of all transitively reachable reactive names
#' @noRd
expand_reactive_deps <- function(initial, reactives) {
  reactive_names <- vapply(reactives, function(r) r$name, character(1))
  visited <- character()
  queue <- initial

  while (length(queue) > 0) {
    current <- queue[[1]]
    queue <- queue[-1]
    if (current %in% visited) {
      next
    }
    visited <- c(visited, current)

    ridx <- match(current, reactive_names)
    if (is.na(ridx)) {
      cli::cli_warn(
        "Reactive {.val {current}} referenced as a dependency but not found
         in the reactive definitions. Its upstream inputs may be missing
         from the tool group."
      )
      next
    }
    upstream <- reactives[[ridx]]$reactive_deps %||% character()
    for (dep in upstream) {
      if (!(dep %in% visited)) {
        queue <- c(queue, dep)
      }
    }
  }

  visited
}

#' Find connected components in the dependency graph
#'
#' Uses union-find to group nodes that are transitively connected.
#'
#' @param graph A graph list with nodes and edges
#' @return List of components, each a character vector of node IDs
#' @noRd
find_connected_components <- function(graph) {
  node_ids <- names(graph$nodes)
  if (length(node_ids) == 0) {
    return(list())
  }

  # Union-find
  parent <- setNames(node_ids, node_ids)

  find_root <- function(x) {
    while (parent[[x]] != x) {
      parent[[x]] <<- parent[[parent[[x]]]] # Path compression
      x <- parent[[x]]
    }
    x
  }

  union_nodes <- function(a, b) {
    ra <- find_root(a)
    rb <- find_root(b)
    if (ra != rb) {
      parent[[ra]] <<- rb
    }
  }

  # Union all edges
  for (edge in graph$edges) {
    if (edge$from %in% node_ids && edge$to %in% node_ids) {
      union_nodes(edge$from, edge$to)
    }
  }

  # Group by root
  groups <- list()
  for (nid in node_ids) {
    root <- find_root(nid)
    if (is.null(groups[[root]])) {
      groups[[root]] <- character()
    }
    groups[[root]] <- c(groups[[root]], nid)
  }

  unname(groups)
}

#' Create a tool group from a connected component
#'
#' @param component Character vector of node IDs in this component
#' @param ir The ShinyAppIR object
#' @return A tool group list
#' @noRd
make_tool_group <- function(component, ir) {
  input_nodes <- component[grepl("^input:", component)]
  output_nodes <- component[grepl("^output:", component)]
  reactive_nodes <- component[grepl("^reactive:", component)]

  input_ids <- sub("^input:", "", input_nodes)
  output_ids <- sub("^output:", "", output_nodes)
  reactive_names <- sub("^reactive:", "", reactive_nodes)

  # Gather structured input info
  input_args <- lapply(input_ids, function(id) {
    idx <- which(vapply(ir$inputs, function(inp) inp$id == id, logical(1)))
    if (length(idx) > 0) {
      ir$inputs[[idx[1]]]
    } else {
      list(id = id, type = "unknown", label = id)
    }
  })

  # Gather structured output info
  output_targets <- lapply(output_ids, function(id) {
    idx <- which(vapply(ir$outputs, function(out) out$id == id, logical(1)))
    if (length(idx) > 0) {
      ir$outputs[[idx[1]]]
    } else {
      list(id = id, type = "unknown")
    }
  })

  # Build a descriptive name from outputs
  name <- if (length(output_ids) > 0) {
    paste0("update_", paste(output_ids, collapse = "_and_"))
  } else if (length(input_ids) > 0) {
    paste0("set_", paste(input_ids, collapse = "_and_"))
  } else {
    "unnamed_group"
  }

  # Build description
  input_labels <- vapply(
    input_args,
    function(a) a$label %||% a$id,
    character(1)
  )
  output_labels <- vapply(output_targets, function(o) o$id, character(1))
  description <- sprintf(
    "Update %s based on %s",
    paste(output_labels, collapse = " and "),
    paste(input_labels, collapse = ", ")
  )

  list(
    name = name,
    input_args = input_args,
    output_targets = output_targets,
    reactive_names = reactive_names,
    description = description
  )
}

#' Check for patterns that cannot be automatically converted
#'
#' @param ir A ShinyAppIR object
#' @return Character vector of warning messages
#' @noRd
check_unresolvable_patterns <- function(ir) {
  warnings <- character()

  # Check for dynamic UI (renderUI / uiOutput)
  has_dynamic_ui <- any(vapply(
    ir$outputs,
    function(o) o$type %in% c("ui", "html"),
    logical(1)
  ))
  if (has_dynamic_ui) {
    warnings <- c(
      warnings,
      "App uses dynamic UI (uiOutput/renderUI) which requires manual conversion."
    )
  }

  # Check for file upload
  has_file_input <- any(vapply(
    ir$inputs,
    function(inp) identical(inp$fn_name, "fileInput"),
    logical(1)
  ))
  if (has_file_input) {
    warnings <- c(
      warnings,
      "App uses fileInput which is not supported in MCP Apps."
    )
  }

  # Check for observers with side effects
  if (length(ir$observers) > 0) {
    warnings <- c(
      warnings,
      sprintf(
        "App has %d observer(s) that may contain side effects requiring manual review.",
        length(ir$observers)
      )
    )
  }

  # Check for download handlers
  has_download <- any(vapply(
    ir$outputs,
    function(o) identical(o$type, "download"),
    logical(1)
  ))
  if (has_download) {
    warnings <- c(
      warnings,
      "App uses downloadButton/downloadHandler which requires manual conversion."
    )
  }

  warnings
}

#' Print method for ReactiveAnalysis
#' @param x A ReactiveAnalysis object
#' @param ... Ignored
#' @export
print.ReactiveAnalysis <- function(x, ...) {
  cli::cli_h1("Reactive Analysis")
  cli::cli_text("Nodes: {length(x$graph$nodes)}")
  cli::cli_text("Edges: {length(x$graph$edges)}")
  cli::cli_text("Tool groups: {length(x$tool_groups)}")
  if (length(x$warnings) > 0) {
    cli::cli_h2("Warnings")
    for (w in x$warnings) {
      cli::cli_alert_warning(w)
    }
  }
  invisible(x)
}
