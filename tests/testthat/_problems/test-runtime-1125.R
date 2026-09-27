# Extracted from test-runtime.R:1125

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
  shiny::checkboxInput("hide", "Hide", FALSE),
  shiny::tabsetPanel(
    id = "tabs",
    shiny::tabPanel("A", "a"),
    shiny::tabPanel("B", "b")
  )
)
server <- function(input, output, session) {
  shiny::observeEvent(
    input$hide,
    if (isTRUE(input$hide)) {
      shiny::hideTab("tabs", "B")
    } else {
      shiny::showTab("tabs", "B")
    },
    ignoreInit = TRUE
  )
}
app <- rt_app(ui, server, name = "tabs")
view <- rt_meta(rt_open(app))
res <- rt_update(app, view, inputs = list(hide = TRUE), changed = "hide")
expect_null(res$isError)
change <- rt_meta(res)$uiChanges[[1]]
expect_identical(change$op, "tab-visibility")
expect_identical(change$id, "tabs")
