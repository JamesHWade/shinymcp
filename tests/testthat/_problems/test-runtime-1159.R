# Extracted from test-runtime.R:1159

# prequel ----------------------------------------------------------------------
cars_text_app <- function(...) {
  ui <- shiny::fluidPage(
    shiny::selectInput("xvar", "X", c("wt", "hp", "disp")),
    shiny::selectInput("yvar", "Y", c("mpg", "qsec")),
    shiny::numericInput("n", "Rows", 3, min = 1, max = 32),
    shiny::textOutput("summary"),
    shiny::textOutput("xonly")
  )
  server <- function(input, output, session) {
    output$summary <- shiny::renderText(
      paste("x:", input$xvar, "y:", input$yvar, "n:", input$n)
    )
    output$xonly <- shiny::renderText(paste("x is", input$xvar))
  }
  rt_app(ui, server, name = "cars", ...)
}
faithful_plot_app <- function(...) {
  ui <- shiny::fluidPage(
    shiny::numericInput("bins", "Bins", 10),
    shiny::plotOutput("hist", height = "300px"),
    shiny::textOutput("dims")
  )
  server <- function(input, output, session) {
    output$hist <- shiny::renderPlot(
      graphics::hist(datasets::faithful$eruptions, breaks = input$bins)
    )
    output$dims <- shiny::renderText(paste(
      session$clientData$output_hist_width,
      session$clientData$output_hist_height,
      session$clientData$pixelratio
    ))
  }
  rt_app(ui, server, name = "faithful", ...)
}

# test -------------------------------------------------------------------------
skip_if_not_installed("shiny")
ui <- shiny::fluidPage(
  shiny::actionButton("add", "Add"),
  shiny::actionButton("drop", "Drop"),
  shiny::tabsetPanel(id = "tabs", shiny::tabPanel("A", "a"))
)
server <- function(input, output, session) {
  shiny::observeEvent(input$add, {
    shiny::insertTab("tabs", shiny::tabPanel("B", "b"), target = "A")
  })
  shiny::observeEvent(input$drop, shiny::removeTab("tabs", "A"))
}
app <- rt_app(ui, server, name = "tab-edits")
view <- rt_meta(rt_open(app))
added <- rt_meta(rt_update(app, view, inputs = list(add = 1), changed = "add"))
insert <- added$uiChanges[[1]]
expect_identical(insert$op, "insert-tab")
expect_identical(insert$id, "tabs")
expect_identical(insert$target, "A")
expect_identical(insert$position, "after")
expect_match(insert$li$html, "data-value=\"B\"", fixed = TRUE)
expect_match(insert$div$html, "tab-tsid-id", fixed = TRUE)
dropped <- rt_meta(rt_update(
  app,
  added,
  inputs = list(add = 1, drop = 1),
  changed = "drop"
))
expect_identical(
  dropped$uiChanges[[1]],
  list(op = "remove-tab", id = "tabs", target = "A")
)
