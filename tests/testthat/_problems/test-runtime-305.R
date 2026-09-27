# Extracted from test-runtime.R:305

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
app <- cars_text_app()
tools <- app$tools()
expect_named(tools, c("cars", "cars_view"))
expect_null(tools$cars$visibility)
expect_identical(tools$cars_view$visibility, "app")
expect_identical(tools$cars$source, "runtime")
expect_identical(
  tools$cars$annotations,
  list(readOnlyHint = FALSE, openWorldHint = FALSE)
)
props <- tools$cars$input_schema$properties
expect_named(props, c("xvar", "yvar", "n", "view"))
expect_identical(unclass(props$xvar$enum), c("wt", "hp", "disp"))
expect_identical(props$view$type, "string")
view_props <- tools$cars_view$input_schema$properties
expect_setequal(
  names(view_props),
  c(
    "action",
    "instance",
    "inputs",
    "changed",
    "events",
    "kinds",
    "sizes",
    "pixelRatio",
    "revision",
    "host",
    "output",
    "body",
    "sync",
    "dependency",
    "all"
  )
)
expect_setequal(
  unclass(view_props$action$enum),
  c("update", "download", "data", "close")
)
