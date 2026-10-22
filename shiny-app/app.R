library(shiny)
library(splines)
library(bslib)
library(ggplot2)

# --------------------------------------------------
# LOAD TRAINED MODELS
# --------------------------------------------------

freq_glm    <- readRDS("../models/freq_model.rds")
sev_glm     <- readRDS("../models/sev_model.rds")
percentiles <- readRDS("../models/portfolio_percentiles.rds")

# --------------------------------------------------
# HELPER FUNCTIONS
# --------------------------------------------------

# Expected claims per policy year (Poisson GLM, exposure set to one year)
predict_frequency <- function(df) {
  df$Exposure <- 1
  predict(freq_glm, newdata = df, type = "response")
}

# Expected cost per claim (Gamma GLM with a log link)
predict_severity <- function(df) predict(sev_glm, newdata = df, type = "response")

expected_premium <- function(df, loading = 0) {
  predict_frequency(df) * predict_severity(df) * (1 + loading)
}

# Share of the holdout portfolio with a lower pure premium
portfolio_percentile <- function(pure) {
  approx(percentiles, seq(0, 100, by = 1), xout = pure, rule = 2, ties = "ordered")$y
}

# --------------------------------------------------
# THEME
# --------------------------------------------------

theme <- bs_theme(
  version = 5,
  bg = "#f7f6f2",
  fg = "#111614",
  primary = "#94600f",
  base_font = font_google("Lato")
)

# --------------------------------------------------
# UI
# --------------------------------------------------

ui <- fluidPage(
  theme = theme,
  
  fluidRow(
    column(
      12,
      h1("Health Insurance Pricing Dashboard",
         class = "text-center mt-4 mb-1"),
      p(
        "Frequency and severity pricing model",
        class = "text-center text-muted mb-4"
      )
    )
  ),
  
  fluidRow(
    
    # -------- Inputs --------
    column(
      4,
      
      card(
        card_header("Policyholder characteristics"),
        sliderInput("age", "Age", min = 18, max = 85, value = 30),
        sliderInput("bmi", "BMI", min = 18, max = 45, value = 25, step = 0.1),
        sliderInput("children", "Number of children", min = 0, max = 5, value = 0),
        selectInput("sex", "Sex", choices = c("male", "female")),
        selectInput("smoker", "Smoking status", choices = c("no", "yes")),
        selectInput(
          "region",
          "Region",
          choices = c("southeast", "southwest", "northeast", "northwest")
        )
      ),
      
      card(
        card_header("Pricing assumptions"),
        sliderInput(
          "loading",
          "Total loading (expenses and profit)",
          min = 0,
          max = 1,
          value = 0.30,
          step = 0.01
        )
      )
    ),
    
    # -------- Outputs --------
    column(
      8,
      
      card(
        card_header("Indicative annual premium"),
        h2(
          textOutput("premium"),
          class = "text-center fw-bold"
        ),
        uiOutput("risk_badge"),
        p(
          "Expected annual premium for one policy year, including loadings.",
          class = "text-center text-muted"
        )
      ),
      
      card(
        card_header("Pricing breakdown"),
        tableOutput("breakdown")
      ),
      
      card(
        card_header("Premium by age, other factors held constant"),
        plotOutput("age_curve", height = "250px")
      )
    )
  ),
  
  fluidRow(
    column(
      12,
      hr(),
      p(
        "Synthetic data. Demonstration use only.",
        class = "text-center text-muted"
      )
    )
  )
)

# --------------------------------------------------
# SERVER
# --------------------------------------------------

server <- function(input, output, session) {
  
  user_data <- reactive({
    data.frame(
      Age = input$age,
      Sex = factor(input$sex, levels = c("female", "male")),
      BMI = input$bmi,
      Smoker = factor(input$smoker, levels = c("no", "yes")),
      Region = factor(
        input$region,
        levels = c("northeast", "northwest", "southeast", "southwest")
      ),
      Children = input$children
    )
  })
  
  premium_val <- reactive({
    expected_premium(user_data(), input$loading)
  })
  
  # -------- Premium Text --------
  output$premium <- renderText({
    paste0(
      "R ",
      format(round(premium_val(), 2), big.mark = ",")
    )
  })
  
  # -------- Risk Badge --------
  # Risk class from the quartiles of the pure premium on the holdout portfolio
  output$risk_badge <- renderUI({
    pct <- portfolio_percentile(expected_premium(user_data()))
    risk_class <- if (pct < 25) {
      list("Low risk", "success")
    } else if (pct < 50) {
      list("Moderate risk", "info")
    } else if (pct < 75) {
      list("High risk", "warning")
    } else {
      list("Very high risk", "danger")
    }

    tags$div(
      class = "text-center",
      tags$span(class = paste0("badge bg-", risk_class[[2]], " fs-6 mt-2"), risk_class[[1]]),
      tags$p(
        class = "text-muted mt-2 mb-0",
        sprintf("Higher pure premium than %.0f%% of the portfolio", pct)
      )
    )
  })
  
  # -------- Breakdown --------
  output$breakdown <- renderTable({
    freq <- predict_frequency(user_data())
    sev  <- predict_severity(user_data())
    pure <- freq * sev
    
    data.frame(
      Metric = c(
        "Expected claims per year",
        "Expected cost per claim",
        "Pure premium",
        "Final premium"
      ),
      Value = c(
        round(freq, 4),
        round(sev, 2),
        round(pure, 2),
        round(premium_val(), 2)
      )
    )
  })
  
  # -------- Age Curve --------
  output$age_curve <- renderPlot({
    
    age_df <- data.frame(
      Age = 18:85,
      Sex = input$sex,
      BMI = input$bmi,
      Smoker = input$smoker,
      Region = input$region,
      Children = input$children
    )
    
    age_df$Premium <- expected_premium(age_df, input$loading)
    
    ggplot(age_df, aes(Age, Premium)) +
      geom_line(color = "#e0a449", linewidth = 1.2) +
      geom_vline(xintercept = input$age, linetype = "dashed", alpha = 0.6) +
      theme_minimal(base_size = 12) +
      theme(
        plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA),
        text = element_text(color = "black"),
        axis.text = element_text(color = "black")
      ) +
      labs(
        x = "Age",
        y = "Annual premium"
      )
  })
}

shinyApp(ui, server)
