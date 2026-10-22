library(shiny)
library(splines)
library(MASS)
library(bslib)
library(ggplot2)

# --------------------------------------------------
# LOAD TRAINED MODELS
# --------------------------------------------------

freq_glm    <- readRDS("../models/freq_model.rds")
sev_glm     <- readRDS("../models/sev_model.rds")
percentiles <- readRDS("../models/portfolio_percentiles.rds")
tariff      <- readRDS("../models/tariff.rds")

PROVINCES <- freq_glm$xlevels$Province
PLANS <- freq_glm$xlevels$Plan

# --------------------------------------------------
# HELPER FUNCTIONS
# --------------------------------------------------

# Log-scale prediction per policy year and its standard error, from the
# covariance matrix saved with the model (the delta method on the log link)
predict_log <- function(model, df) {
  df$Exposure <- 1
  tt <- delete.response(terms(model))
  mf <- model.frame(tt, df, xlev = model$xlevels)
  X <- model.matrix(tt, mf, contrasts.arg = model$contrasts)
  list(fit = drop(X %*% coef(model)), se = sqrt(rowSums((X %*% model$V) * X)))
}

# Expected claims per year (negative binomial GLM), cost per claim (Gamma
# GLM) and expected annual cost with its 95% interval. The two models'
# estimates are independent, so the log-scale variances add.
price <- function(df) {
  f <- predict_log(freq_glm, df)
  s <- predict_log(sev_glm, df)
  se <- sqrt(f$se^2 + s$se^2)
  data.frame(
    frequency = exp(f$fit),
    severity = exp(s$fit),
    pure = exp(f$fit + s$fit),
    low = exp(f$fit + s$fit - qnorm(0.975) * se),
    high = exp(f$fit + s$fit + qnorm(0.975) * se),
    tariff = exp(f$fit + s$fit) * tariff_ratio(df)
  )
}

# The tariff replaces the fitted age and sex factor with each sex's
# non-decreasing tariff curve; this is the ratio of the two
tariff_ratio <- function(df) {
  i <- match(paste(df$Age, df$Sex), paste(tariff$Age, tariff$Sex))
  tariff$tariff[i] / tariff$risk[i]
}

# Share of holdout members on the same plan with a lower pure premium
plan_percentile <- function(pure, plan) {
  approx(percentiles[[plan]], seq(0, 100, by = 1), xout = pure, rule = 2, ties = "ordered")$y
}

rand <- function(x) paste0("R ", format(round(x), big.mark = ","))

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
        "Frequency and severity pricing model for a South African portfolio",
        class = "text-center text-muted mb-4"
      )
    )
  ),

  fluidRow(

    # -------- Inputs --------
    column(
      4,

      card(
        card_header("Member characteristics"),
        sliderInput("age", "Age", min = 18, max = 85, value = 45),
        sliderInput("bmi", "BMI", min = 16, max = 50, value = 27.5, step = 0.1),
        sliderInput("children", "Number of children", min = 0, max = 5, value = 1),
        selectInput("sex", "Sex", choices = c("female", "male")),
        selectInput("smoker", "Smoking status", choices = c("no", "yes")),
        selectInput("province", "Province", choices = PROVINCES),
        selectInput("plan", "Plan", choices = PLANS, selected = "Standard")
      ),

      card(
        card_header("Pricing assumptions"),
        sliderInput(
          "loading",
          "Loading for expenses",
          min = 0,
          max = 0.4,
          value = 0.15,
          step = 0.01
        )
      )
    ),

    # -------- Outputs --------
    column(
      8,

      card(
        card_header("Indicative monthly premium"),
        h2(
          textOutput("premium"),
          class = "text-center fw-bold"
        ),
        p(textOutput("premium_detail"), class = "text-center text-muted mb-0"),
        uiOutput("risk_badge")
      ),

      card(
        card_header("Pricing breakdown"),
        tableOutput("breakdown")
      ),

      card(
        card_header("Monthly premium by age, other factors held constant"),
        plotOutput("age_curve", height = "250px")
      )
    )
  ),

  fluidRow(
    column(
      12,
      hr(),
      p(
        paste(
          "Synthetic data. Demonstration use only. The tariff smooths the age curve so the premium",
          "never falls with age, collecting the same total premium within each sex."
        ),
        class = "text-center text-muted"
      )
    )
  )
)

# --------------------------------------------------
# SERVER
# --------------------------------------------------

server <- function(input, output, session) {

  member <- function(age = input$age) {
    data.frame(
      Age = age,
      Sex = factor(input$sex, levels = c("female", "male")),
      BMI = input$bmi,
      Smoker = factor(input$smoker, levels = c("no", "yes")),
      Province = factor(input$province, levels = PROVINCES),
      Plan = factor(input$plan, levels = PLANS),
      Children = input$children
    )
  }

  quote <- reactive(price(member()))
  monthly <- function(annual) annual * (1 + input$loading) / 12

  # -------- Premium Text --------
  output$premium <- renderText({
    paste(rand(monthly(quote()$tariff)), "a month")
  })

  output$premium_detail <- renderText({
    q <- quote()
    sprintf("%s a year. Risk premium %s a month, 95%% interval %s to %s.",
            rand(q$tariff * (1 + input$loading)), rand(monthly(q$pure)), rand(monthly(q$low)),
            rand(monthly(q$high)))
  })

  # -------- Risk Badge --------
  # Risk class from the quartiles of the pure premium among holdout members
  # on the same plan
  output$risk_badge <- renderUI({
    pct <- plan_percentile(quote()$pure, input$plan)
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
        sprintf("Higher expected cost than %.0f%% of members on the %s plan", pct, input$plan)
      )
    )
  })

  # -------- Breakdown --------
  output$breakdown <- renderTable({
    q <- quote()
    data.frame(
      Metric = c(
        "Expected claims per year",
        "Expected cost per claim",
        "Expected claims cost per year",
        "Tariff age smoothing",
        "Annual premium",
        "Monthly premium"
      ),
      Value = c(
        format(round(q$frequency, 3), nsmall = 3),
        rand(q$severity),
        rand(q$pure),
        sprintf("x %.3f", q$tariff / q$pure),
        rand(q$tariff * (1 + input$loading)),
        rand(monthly(q$tariff))
      )
    )
  })

  # -------- Age Curve --------
  output$age_curve <- renderPlot({

    age_df <- cbind(data.frame(Age = 18:85), price(member(18:85)))

    ggplot(age_df, aes(Age)) +
      geom_ribbon(aes(ymin = monthly(low), ymax = monthly(high)), fill = "#e0a449", alpha = 0.25) +
      geom_line(aes(y = monthly(pure), linetype = "Risk premium"), color = "#e0a449", linewidth = 1) +
      geom_line(aes(y = monthly(tariff), linetype = "Tariff premium"), color = "#111614", linewidth = 1) +
      scale_linetype_manual(values = c("Risk premium" = "dashed", "Tariff premium" = "solid"), name = NULL) +
      geom_vline(xintercept = input$age, linetype = "dashed", alpha = 0.6) +
      scale_y_continuous(labels = rand, limits = c(0, NA)) +
      theme_minimal(base_size = 12) +
      theme(
        plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA),
        text = element_text(color = "black"),
        axis.text = element_text(color = "black"),
        legend.position = "bottom"
      ) +
      labs(
        x = "Age",
        y = "Monthly premium"
      )
  })
}

shinyApp(ui, server)
