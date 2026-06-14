# generate_tools output is stable for the simple app

    Code
      cat(generate_tools(analysis$tool_groups))
    Output
      # Generated MCP App Tools
      # Each tool corresponds to a reactive computation group from the original Shiny app
      
      library(ellmer)
      
      update_result <- ellmer::tool(
        fun = function(x) {
          # Original logic for output 'result':
          # renderText({
          #     paste("You chose:", input$x)
          # })
          paste("Result for:", x)
        },
        name = "update_result",
        description = "Update result based on Choose:",
        arguments = list(
          x = ellmer::type_string("Choose:")
        ),
        annotations = ellmer::tool_annotations(
          read_only_hint = TRUE,
          destructive_hint = FALSE,
          open_world_hint = FALSE,
          idempotent_hint = TRUE
        )
      )
      
      # Collect all tools
      tools <- list(update_result)

