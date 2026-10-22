# --------------------------------------------------
# Model Training and Validation for Health Insurance Pricing
# --------------------------------------------------
# Fits a Poisson GLM for claim frequency (per policy year, with an
# exposure offset) and a Gamma GLM for claim severity (average cost per
# claim, weighted by claim count) on 80% of the synthetic portfolio, then
# checks both on the 20% holdout and against the true parameters used to
# generate the data.
#
# Outputs:
#   models/freq_model.rds, models/sev_model.rds   fitted models
#   models/portfolio_percentiles.rds              holdout pure premium percentiles
#   reports/validation.md                         holdout results
#   dashboard/src/model.json                      model export for the dashboard
#   dashboard/test/parity-cases.json              R predictions for the parity test
#
# Run from the project root: Rscript scripts/model_training.R
# --------------------------------------------------

library(splines)
library(jsonlite)

insurance_data <- read.csv("data/synthetic_health_insurance_data.csv")
insurance_data$Sex <- factor(insurance_data$Sex, levels = c("female", "male"))
insurance_data$Smoker <- factor(insurance_data$Smoker, levels = c("no", "yes"))
insurance_data$Region <- factor(
  insurance_data$Region,
  levels = c("northeast", "northwest", "southeast", "southwest")
)

# --------------------------------------------------
# TRAIN / HOLDOUT SPLIT
# --------------------------------------------------

set.seed(2026)
is_train <- runif(nrow(insurance_data)) < 0.8
train <- insurance_data[is_train, ]
test <- insurance_data[!is_train, ]

# --------------------------------------------------
# FREQUENCY MODEL (Poisson, log link, exposure offset)
# --------------------------------------------------

freq_model <- glm(
  ClaimCount ~ ns(Age, df = 4) + ns(BMI, df = 4) + Sex + Smoker + Children + Region +
    offset(log(Exposure)),
  data = train,
  family = poisson(link = "log")
)

freq_dispersion <- sum(residuals(freq_model, type = "pearson")^2) / freq_model$df.residual

# --------------------------------------------------
# SEVERITY MODEL (Gamma, log link, per claim)
# --------------------------------------------------
# The response is the average cost per claim on policies with at least one
# claim. Weighting by claim count makes this equivalent to fitting each
# claim separately, because the variance of an average of k claims is the
# per-claim variance divided by k.

sev_train <- train[train$ClaimCount > 0, ]
sev_train$AvgCost <- sev_train$Charges / sev_train$ClaimCount

sev_model <- glm(
  AvgCost ~ ns(Age, df = 4) + ns(BMI, df = 4) + Sex + Smoker + Children + Region,
  data = sev_train,
  family = Gamma(link = "log"),
  weights = ClaimCount
)

sev_dispersion <- summary(sev_model)$dispersion

# --------------------------------------------------
# PREDICTION
# --------------------------------------------------

predict_frequency <- function(df) {
  df$Exposure <- 1
  predict(freq_model, newdata = df, type = "response")
}
predict_severity <- function(df) predict(sev_model, newdata = df, type = "response")
predict_pure <- function(df) predict_frequency(df) * predict_severity(df)

# True expected cost per policy year under the generating model. BMI is
# rounded to one decimal in the data, so this is very slightly different
# from the values used to simulate.
true_frequency <- function(df) {
  exp(-2.5 + 0.015 * df$Age + 0.03 * (df$BMI - 25) + 0.6 * (df$Smoker == "yes") +
        0.08 * df$Children + 0.2 * (df$Region == "southeast"))
}
true_severity <- function(df) {
  exp(8 + 0.01 * df$Age + 0.02 * (df$BMI - 25) + 0.5 * (df$Smoker == "yes") +
        0.1 * df$Children + 0.5 * 0.8^2)
}

# --------------------------------------------------
# HOLDOUT VALIDATION
# --------------------------------------------------

test$pred_rate <- predict_pure(test)
test$true_rate <- true_frequency(test) * true_severity(test)
test$pred_cost <- test$pred_rate * test$Exposure
test$true_cost <- test$true_rate * test$Exposure
test$pred_claims <- predict_frequency(test) * test$Exposure

holdout <- list(
  policies = nrow(test),
  exposure = sum(test$Exposure),
  claims = sum(test$ClaimCount),
  claims_ae = sum(test$ClaimCount) / sum(test$pred_claims),
  cost_ae = sum(test$Charges) / sum(test$pred_cost),
  freq_deviance_explained = NA_real_
)

# Poisson deviance explained on the holdout, against an exposure-only model.
pois_dev <- function(y, mu) 2 * sum(ifelse(y > 0, y * log(y / mu), 0) - (y - mu))
null_mu <- test$Exposure * sum(train$ClaimCount) / sum(train$Exposure)
holdout$freq_deviance_explained <-
  1 - pois_dev(test$ClaimCount, test$pred_claims) / pois_dev(test$ClaimCount, null_mu)

# Exposure-weighted Lorenz curve and Gini: policies sorted from lowest to
# highest predicted cost per policy year, against their share of actual cost.
lorenz <- function(score) {
  o <- order(score)
  x <- c(0, cumsum(test$Exposure[o]) / sum(test$Exposure))
  y <- c(0, cumsum(test$Charges[o]) / sum(test$Charges))
  list(x = x, y = y, gini = 1 - 2 * sum(diff(x) * (head(y, -1) + tail(y, -1)) / 2))
}
lorenz_model <- lorenz(test$pred_rate)
lorenz_true <- lorenz(test$true_rate)
holdout$gini_model <- lorenz_model$gini
holdout$gini_true <- lorenz_true$gini

# Lift: ten bands of equal exposure by predicted cost per policy year.
o <- order(test$pred_rate)
band <- pmin(10, floor(10 * (cumsum(test$Exposure[o]) - test$Exposure[o] / 2) /
                         sum(test$Exposure)) + 1)
lift <- lapply(1:10, function(b) {
  rows <- o[band == b]
  e <- sum(test$Exposure[rows])
  list(
    band = b,
    policies = length(rows),
    predicted = sum(test$pred_cost[rows]) / e,
    actual = sum(test$Charges[rows]) / e,
    true = sum(test$true_cost[rows]) / e
  )
})

# --------------------------------------------------
# RELATIVITIES AGAINST THE TRUE PARAMETERS
# --------------------------------------------------
# The base profile is the reference level of every factor: age 40, BMI 25,
# female, non-smoker, northeast, no children.

base <- data.frame(Age = 40, BMI = 25, Sex = "female", Smoker = "no",
                   Region = "northeast", Children = 0)

factor_rows <- list(
  list(factor = "Sex", level = "male", term = "Sexmale",
       true_freq = 1, true_sev = 1),
  list(factor = "Smoker", level = "yes", term = "Smokeryes",
       true_freq = exp(0.6), true_sev = exp(0.5)),
  list(factor = "Children", level = "each child", term = "Children",
       true_freq = exp(0.08), true_sev = exp(0.1)),
  list(factor = "Region", level = "northwest", term = "Regionnorthwest",
       true_freq = 1, true_sev = 1),
  list(factor = "Region", level = "southeast", term = "Regionsoutheast",
       true_freq = exp(0.2), true_sev = 1),
  list(factor = "Region", level = "southwest", term = "Regionsouthwest",
       true_freq = 1, true_sev = 1)
)

relativity <- function(model, term) {
  est <- coef(model)[[term]]
  se <- sqrt(vcov(model)[term, term])
  c(est = exp(est), lo = exp(est - 1.96 * se), hi = exp(est + 1.96 * se))
}

factors <- lapply(factor_rows, function(r) {
  f <- relativity(freq_model, r$term)
  s <- relativity(sev_model, r$term)
  list(
    factor = r$factor, level = r$level,
    freq = unname(f["est"]), freq_lo = unname(f["lo"]), freq_hi = unname(f["hi"]),
    sev = unname(s["est"]), sev_lo = unname(s["lo"]), sev_hi = unname(s["hi"]),
    true_freq = r$true_freq, true_sev = r$true_sev
  )
})

# --------------------------------------------------
# EXPORT FOR THE DASHBOARD
# --------------------------------------------------
# Both models are additive on the log scale, so a prediction is the base
# log value plus one term per rating factor. Age and BMI are exported as
# tables of their spline terms at every value the dashboard accepts
# (whole years 18 to 85, BMI 18.0 to 45.0 in steps of 0.1), which makes
# the dashboard's predictions identical to R's.

ages <- 18:85
bmis <- round(seq(18, 45, by = 0.1), 1)

term_table <- function(predict_fn, var, values) {
  grid <- base[rep(1, length(values)), ]
  grid[[var]] <- values
  log(predict_fn(grid)) - log(predict_fn(base))
}

export_model <- function(predict_fn, model, dispersion) {
  cf <- coef(model)
  list(
    base = log(predict_fn(base)),
    age = term_table(predict_fn, "Age", ages),
    bmi = term_table(predict_fn, "BMI", bmis),
    sex = list(female = 0, male = cf[["Sexmale"]]),
    smoker = list(no = 0, yes = cf[["Smokeryes"]]),
    children = cf[["Children"]],
    region = list(
      northeast = 0,
      northwest = cf[["Regionnorthwest"]],
      southeast = cf[["Regionsoutheast"]],
      southwest = cf[["Regionsouthwest"]]
    ),
    dispersion = dispersion
  )
}

true_curve <- function(var, values) {
  grid <- base[rep(1, length(values)), ]
  grid[[var]] <- values
  list(
    freq = log(true_frequency(grid)) - log(true_frequency(base)),
    sev = log(true_severity(grid)) - log(true_severity(base))
  )
}

# Portfolio distribution of the annual pure premium on the holdout, used to
# place a quoted profile in the portfolio and to set the risk classes.
percentiles <- unname(quantile(test$pred_rate, probs = seq(0, 1, by = 0.01)))

thin <- function(l, k = 200) {
  i <- unique(round(seq(1, length(l$x), length.out = k)))
  list(x = l$x[i], y = l$y[i])
}

export <- list(
  generated = format(Sys.Date()),
  ranges = list(age = range(ages), bmi = range(bmis), children = c(0, 5)),
  base_profile = as.list(base),
  frequency = export_model(predict_frequency, freq_model, freq_dispersion),
  severity = export_model(predict_severity, sev_model, sev_dispersion),
  true_curves = list(age = true_curve("Age", ages), bmi = true_curve("BMI", bmis)),
  factors = factors,
  portfolio = list(
    percentiles = percentiles,
    mean = mean(test$pred_rate)
  ),
  validation = list(
    train_policies = nrow(train),
    train_claims = sum(train$ClaimCount),
    holdout = holdout,
    lift = lift,
    lorenz_model = thin(lorenz_model),
    lorenz_true = thin(lorenz_true)
  )
)

dir.create("dashboard/src", recursive = TRUE, showWarnings = FALSE)
dir.create("dashboard/test", recursive = TRUE, showWarnings = FALSE)
write_json(export, "dashboard/src/model.json", auto_unbox = TRUE, digits = NA)

# R predictions on random profiles, for the dashboard's parity test.
set.seed(7)
k <- 300
cases <- data.frame(
  Age = sample(ages, k, replace = TRUE),
  BMI = sample(bmis, k, replace = TRUE),
  Sex = sample(levels(insurance_data$Sex), k, replace = TRUE),
  Smoker = sample(levels(insurance_data$Smoker), k, replace = TRUE),
  Region = sample(levels(insurance_data$Region), k, replace = TRUE),
  Children = sample(0:5, k, replace = TRUE)
)
cases$frequency <- predict_frequency(cases)
cases$severity <- predict_severity(cases)
cases$pure <- cases$frequency * cases$severity
write_json(cases, "dashboard/test/parity-cases.json", digits = NA)

# --------------------------------------------------
# SAVE MODELS
# --------------------------------------------------
# Drop the training data and per-row fitted values; prediction only needs
# the formula, the spline knots and the coefficients.

strip <- function(m) {
  m[c("data", "model", "y", "residuals", "fitted.values", "effects", "weights",
      "prior.weights", "linear.predictors", "offset")] <- NULL
  m$qr <- list(pivot = m$qr$pivot, rank = m$qr$rank)
  class(m$qr) <- "qr"
  attr(m$terms, ".Environment") <- globalenv()
  m
}
dir.create("models", showWarnings = FALSE)
saveRDS(strip(freq_model), "models/freq_model.rds")
saveRDS(strip(sev_model), "models/sev_model.rds")
saveRDS(percentiles, "models/portfolio_percentiles.rds")

# --------------------------------------------------
# VALIDATION REPORT
# --------------------------------------------------

fmt <- function(x, d = 3) formatC(x, format = "f", digits = d, big.mark = ",")
lines <- c(
  "# Validation results",
  "",
  "Written by `scripts/model_training.R`. The models are fitted on a random 80% of the",
  "synthetic portfolio and checked on the remaining 20%. Because the data is synthetic,",
  "the fitted effects can also be compared with the true parameters used to generate it.",
  "",
  "## Fit",
  "",
  sprintf("- Training set: %s policies, %s claims.", fmt(nrow(train), 0), fmt(sum(train$ClaimCount), 0)),
  sprintf("- Frequency model Pearson dispersion: %s (1 means no overdispersion).", fmt(freq_dispersion)),
  sprintf("- Severity model Gamma dispersion: %s (the true lognormal severity has a squared coefficient of variation of %s).",
          fmt(sev_dispersion), fmt(exp(0.8^2) - 1)),
  "",
  "## Holdout",
  "",
  sprintf("- Holdout set: %s policies, %s policy years, %s claims.",
          fmt(holdout$policies, 0), fmt(holdout$exposure, 0), fmt(holdout$claims, 0)),
  sprintf("- Actual over expected claim count: %s.", fmt(holdout$claims_ae)),
  sprintf("- Actual over expected claim cost: %s.", fmt(holdout$cost_ae)),
  sprintf("- Poisson deviance explained by the frequency model: %s%%.", fmt(100 * holdout$freq_deviance_explained, 1)),
  sprintf("- Gini of the pure premium: %s, against %s for the true generating model.",
          fmt(holdout$gini_model), fmt(holdout$gini_true)),
  "",
  "## Lift by predicted cost band",
  "",
  "Ten bands of equal exposure, from lowest to highest predicted cost per policy year.",
  "",
  "| Band | Policies | Predicted | Actual | True expected |",
  "| --- | --- | --- | --- | --- |",
  vapply(lift, function(l) sprintf("| %d | %s | %s | %s | %s |", l$band, fmt(l$policies, 0),
                                   fmt(l$predicted, 0), fmt(l$actual, 0), fmt(l$true, 0)), ""),
  "",
  "## Relativities against the true parameters",
  "",
  "Multiplicative effect on the base profile, with 95% Wald intervals.",
  "",
  "| Factor | Level | Frequency [95% CI] | True | Severity [95% CI] | True |",
  "| --- | --- | --- | --- | --- | --- |",
  vapply(factors, function(f) sprintf("| %s | %s | %s [%s, %s] | %s | %s [%s, %s] | %s |",
                                      f$factor, f$level, fmt(f$freq), fmt(f$freq_lo), fmt(f$freq_hi),
                                      fmt(f$true_freq), fmt(f$sev), fmt(f$sev_lo), fmt(f$sev_hi),
                                      fmt(f$true_sev)), "")
)
writeLines(lines, "reports/validation.md")
cat(lines, sep = "\n")
