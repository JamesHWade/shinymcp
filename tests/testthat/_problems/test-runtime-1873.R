# Extracted from test-runtime.R:1873

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
skip_if_not_installed("DT")
ui <- shiny::fluidPage(DT::DTOutput("tbl"))
server <- function(input, output, session) {
  output$tbl <- DT::renderDT(utils::head(mtcars[, 1:3]), server = FALSE)
}
app <- rt_app(ui, server, name = "dt")
tbl <- rt_meta(rt_open(app))$outputs$tbl
names <- vapply(tbl$deps, function(d) d$name, character(1))
expect_true("jquery" %in% names)
