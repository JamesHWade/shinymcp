# generate_tools output is stable for the simple app

    Code
      cat(generate_tools(analysis$tool_groups, ir$reactives))
    Output
      # The app's tools, drafted by shinymcp::convert_app().
      #
      # Each tool computes outputs that share inputs in the Shiny app. Its body
      # holds the app's code for them as comments: rewrite it with the tool's
      # arguments in place of input$..., and return each output by its id.
      
      update_result <- ellmer::tool(
        function(x = "a") {
          # From the Shiny app:
          #
          # output$result <- renderText({
          #     paste("You chose:", input$x)
          # })
          list(
            result = "TODO: output$result"
          )
        },
        name = "update_result",
        description = "Update result based on Choose",
        arguments = list(
          x = ellmer::type_enum(c("a", "b", "c"), "Choose", required = FALSE)
        ),
        annotations = ellmer::tool_annotations(read_only_hint = TRUE)
      )
      
      tools <- list(update_result)

