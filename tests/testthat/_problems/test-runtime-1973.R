# Extracted from test-runtime.R:1973

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
download_app <- function() {
  ui <- shiny::fluidPage(
    shiny::numericInput("rows", "Rows", 3),
    shiny::downloadButton("csv", "CSV"),
    shiny::downloadButton("notes", "Notes"),
    shiny::downloadButton("broken", "Broken"),
    shiny::textOutput("count")
  )
  server <- function(input, output, session) {
    output$csv <- shiny::downloadHandler(
      filename = function() paste0("faithful-", input$rows, ".csv"),
      content = function(file) {
        utils::write.csv(
          utils::head(datasets::faithful, input$rows),
          file,
          row.names = FALSE
        )
      }
    )
    output$notes <- shiny::downloadHandler(
      filename = "notes.dat",
      content = function(file) writeLines("some notes", file),
      contentType = "text/plain"
    )
    output$broken <- shiny::downloadHandler(
      filename = "broken.txt",
      content = function(file) stop("no data")
    )
    output$count <- shiny::renderText(paste(input$rows, "rows"))
  }
  rt_app(ui, server, name = "files")
}
dt_request_body <- function(n_columns, start = 0, length = 10) {
  columns <- unlist(lapply(seq_len(n_columns) - 1, function(i) {
    c(
      sprintf("columns[%d][data]=%d", i, i),
      sprintf("columns[%d][name]=", i),
      sprintf("columns[%d][searchable]=true", i),
      sprintf("columns[%d][orderable]=true", i),
      sprintf("columns[%d][search][value]=", i),
      sprintf("columns[%d][search][regex]=false", i)
    )
  }))
  fields <- c(
    "draw=1",
    columns,
    "order[0][column]=0",
    "order[0][dir]=asc",
    paste0("start=", start),
    paste0("length=", length),
    "search[value]=",
    "search[regex]=false",
    "search[caseInsensitive]=true",
    "escape=true"
  )
  pairs <- strsplit(fields, "=", fixed = TRUE)
  paste(
    vapply(
      pairs,
      function(kv) {
        paste0(
          utils::URLencode(kv[[1]], reserved = TRUE),
          "=",
          if (length(kv) > 1) utils::URLencode(kv[[2]], reserved = TRUE) else ""
        )
      },
      character(1)
    ),
    collapse = "&"
  )
}

# test -------------------------------------------------------------------------
skip_if_not_installed("shiny")
ticks <- 0
ui <- shiny::fluidPage(
  shiny::numericInput("n", "N", 1),
  shiny::textOutput("clock")
)
server <- function(input, output, session) {
  output$clock <- shiny::renderText({
    shiny::invalidateLater(500)
    ticks <<- ticks + 1
    paste("tick", ticks)
  })
}
app <- rt_app(ui, server, name = "timer")
view <- rt_meta(rt_open(app))
expect_identical(view$outputs$clock$value, "tick 1")
inst <- rt_instance(app, view$instance)
inst$clock <- inst$clock - 1
meta <- rt_meta(rt_update(app, view, inputs = list(n = 1), changed = "n"))
expect_identical(meta$outputs$clock$value, "tick 3")
