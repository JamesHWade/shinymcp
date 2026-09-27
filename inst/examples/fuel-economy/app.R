# A bslib dashboard served live, with a say in what the model sees.
#
# - bindMcp() marks the inputs the model may set and the outputs it hears
#   about. Unmarked parts (the trend-line checkbox, the plot, the download)
#   are for the person only.
# - mcp_model_context() tells the model what the person is looking at after
#   they change something, in a sentence and a few numbers.
# - mcp_host_context() follows the chat's light or dark theme, so the plot
#   is drawn in colors that suit it.
# - The download button works: the chat client saves the file.
#
# Preview it:
#   shinymcp::preview_app(system.file("examples", "fuel-economy", "app.R", package = "shinymcp"))

library(shiny)
library(bslib)
library(ggplot2)
library(shinymcp)

classes <- sort(unique(mpg$class))

ui <- page_sidebar(
  title = "Fuel economy",
  sidebar = sidebar(
    checkboxGroupInput("class", "Vehicle class", classes, selected = classes) |>
      bindMcp(),
    sliderInput("displ", "Engine size (litres)", 1.6, 7, value = c(1.6, 7), step = 0.1) |>
      bindMcp(),
    radioButtons("metric", "Mileage", c("Highway" = "hwy", "City" = "cty")) |>
      bindMcp(),
    checkboxInput("trend", "Show trend line", TRUE),
    downloadButton("download", "Download these cars")
  ),
  layout_columns(
    fill = FALSE,
    value_box("Cars", textOutput("count") |> bindMcp()),
    value_box("Median mileage", textOutput("median") |> bindMcp())
  ),
  card(
    card_header("Mileage by engine size"),
    plotOutput("scatter", height = "320px")
  ),
  card(
    card_header("Most efficient models"),
    tableOutput("best") |> bindMcp()
  )
)

server <- function(input, output, session) {
  cars <- reactive({
    keep <- mpg$class %in% input$class &
      mpg$displ >= input$displ[1] &
      mpg$displ <= input$displ[2]
    validate(need(any(keep), "No cars match these filters."))
    mpg[keep, ]
  })

  metric_label <- reactive(if (input$metric == "hwy") "Highway" else "City")

  output$count <- renderText(nrow(cars()))
  output$median <- renderText(paste(median(cars()[[input$metric]]), "mpg"))

  output$scatter <- renderPlot(
    {
      # Draw in the chat's colors: light ink on a dark theme. The plot's
      # background is transparent, so the card shows through.
      dark <- identical(mcp_host_context()$theme, "dark")
      ink <- if (dark) "#e6e6e3" else "#262624"
      p <- ggplot(cars(), aes(displ, .data[[input$metric]], colour = class)) +
        geom_point(size = 2.2, alpha = 0.85) +
        labs(x = "Engine size (litres)", y = paste(metric_label(), "mpg"), colour = NULL) +
        theme_minimal(base_size = 14, ink = ink, paper = "transparent")
      if (input$trend) {
        p <- p +
          geom_smooth(
            aes(group = 1),
            method = "loess",
            formula = y ~ x,
            se = FALSE,
            colour = ink,
            linewidth = 0.6
          )
      }
      p
    },
    bg = "transparent"
  )

  output$best <- renderTable({
    best <- cars()[order(-cars()[[input$metric]]), ]
    best <- unique(best[, c("manufacturer", "model", "year", input$metric)])
    names(best)[4] <- paste(metric_label(), "mpg")
    utils::head(best, 6)
  })

  output$download <- downloadHandler(
    filename = "fuel-economy.csv",
    content = function(file) utils::write.csv(cars(), file, row.names = FALSE)
  )

  observe({
    shown <- cars()
    mileage <- shown[[input$metric]]
    mcp_model_context(
      text = sprintf(
        "Showing %d cars (%s) with %s-litre engines; median %s mileage %s mpg.",
        nrow(shown),
        paste(input$class, collapse = ", "),
        paste(input$displ, collapse = " to "),
        tolower(metric_label()),
        stats::median(mileage)
      ),
      data = list(
        classes = input$class,
        engine_litres = input$displ,
        metric = input$metric,
        cars = nrow(shown),
        median_mpg = stats::median(mileage)
      )
    )
  })
}

app <- as_mcp_app(
  shinyApp(ui, server),
  name = "fuel-economy",
  title = "Fuel economy",
  description = paste(
    "Explore fuel economy of 234 car models (1999 and 2008) by class,",
    "engine size, and city or highway mileage."
  )
)

if (interactive()) preview_app(app) else serve(app)
