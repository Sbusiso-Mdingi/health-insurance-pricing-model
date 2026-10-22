# --------------------------------------------------
# Model Training and Validation for Health Insurance Pricing
# --------------------------------------------------
# Compares candidate frequency and severity models on 80% of the synthetic
# portfolio, selects the final models by nested tests, then checks them on
# the 20% holdout and against the true parameters used to generate the
# data. The final models are a negative binomial GLM for claim frequency
# (per policy year, with an exposure offset) and a Gamma GLM for claim
# severity (average cost per claim, weighted by claim count).
#
# Outputs:
#   models/freq_model.rds, models/sev_model.rds   fitted models, with vcov
#   models/portfolio_percentiles.rds              holdout pure premium percentiles by plan
#   models/tariff.rds                             risk and tariff age factors by sex
#   reports/validation.md                         comparison and holdout results
#   dashboard/src/model.json                      model export for the dashboard
#   dashboard/test/parity-cases.json              R predictions for the parity test
#
# Run from the project root: Rscript scripts/model_training.R
# --------------------------------------------------

suppressPackageStartupMessages({
  library(jsonlite)
  library(statmod)
})
source("scripts/simulate.R")
source("scripts/models.R")

insurance_data <- set_levels(read.csv("data/synthetic_health_insurance_data.csv"))

# --------------------------------------------------
# TRAIN / HOLDOUT SPLIT
# --------------------------------------------------

set.seed(2026)
is_train <- runif(nrow(insurance_data)) < 0.8
train <- insurance_data[is_train, ]
test <- insurance_data[!is_train, ]
test_claims <- claims_only(test)

per_year <- function(df) transform(df, Exposure = 1)

# --------------------------------------------------
# HOLDOUT METRICS
# --------------------------------------------------

pois_dev <- function(y, mu) 2 * sum(ifelse(y > 0, y * log(y / mu), 0) - (y - mu))
gamma_dev <- function(y, mu, w) 2 * sum(w * (-log(y / mu) + (y - mu) / mu))
tweedie_dev <- function(y, mu, w, p = 1.6) {
  2 * sum(w * (y^(2 - p) / ((1 - p) * (2 - p)) - y * mu^(1 - p) / (1 - p) + mu^(2 - p) / (2 - p)))
}

# Deviance explained on the holdout, against a model with no rating
# factors fitted on the training set.
freq_null <- sum(train$ClaimCount) / sum(train$Exposure)
sev_null <- sum(train$Charges) / sum(train$ClaimCount)
cost_null <- sum(train$Charges) / sum(train$Exposure)

freq_dev_explained <- function(rate) {
  1 - pois_dev(test$ClaimCount, rate * test$Exposure) /
    pois_dev(test$ClaimCount, freq_null * test$Exposure)
}
sev_dev_explained <- function(mu) {
  1 - gamma_dev(test_claims$AvgCost, mu, test_claims$ClaimCount) /
    gamma_dev(test_claims$AvgCost, sev_null, test_claims$ClaimCount)
}
cost_dev_explained <- function(rate) {
  y <- test$Charges / test$Exposure
  1 - tweedie_dev(y, rate, test$Exposure) / tweedie_dev(y, cost_null, test$Exposure)
}

# Weighted Lorenz curve and Gini: units sorted from lowest to highest score,
# cumulative share of weight against cumulative share of the actual outcome.
lorenz <- function(score, weight, actual) {
  o <- order(score)
  x <- c(0, cumsum(weight[o]) / sum(weight))
  y <- c(0, cumsum(actual[o]) / sum(actual))
  list(x = x, y = y, gini = 1 - 2 * sum(diff(x) * (head(y, -1) + tail(y, -1)) / 2))
}
gini_freq <- function(rate) lorenz(rate, test$Exposure, test$ClaimCount)$gini
gini_sev <- function(mu) lorenz(mu, test_claims$ClaimCount, test_claims$Charges)$gini
gini_cost <- function(rate) lorenz(rate, test$Exposure, test$Charges)$gini

# --------------------------------------------------
# MODEL COMPARISON
# --------------------------------------------------

freq_fits <- lapply(FREQ_CANDIDATES, function(rhs) {
  list(poisson = fit_poisson(rhs, train), negbin = fit_negbin(rhs, train))
})
sev_fits <- lapply(SEV_CANDIDATES, fit_gamma, data = train)

freq_comparison <- do.call(c, lapply(names(freq_fits), function(nm) {
  lapply(c("poisson", "negbin"), function(fam) {
    m <- freq_fits[[nm]][[fam]]
    rate <- predict(m, per_year(test), type = "response")
    list(
      model = nm, family = fam, rhs = FREQ_CANDIDATES[[nm]],
      parameters = length(coef(m)) + (fam == "negbin"),
      aic = AIC(m),
      deviance_explained = freq_dev_explained(rate),
      gini = gini_freq(rate)
    )
  })
}))

sev_comparison <- lapply(names(sev_fits), function(nm) {
  m <- sev_fits[[nm]]
  mu <- predict(m, test_claims, type = "response")
  list(
    model = nm, rhs = SEV_CANDIDATES[[nm]], parameters = length(coef(m)),
    aic = AIC(m), dispersion = pearson_dispersion(m),
    deviance_explained = sev_dev_explained(mu), gini = gini_sev(mu)
  )
})

# Nested tests on the training set, at the 5% level: likelihood ratio
# tests for the negative binomial models, and F tests using the estimated
# dispersion for the Gamma models. The Gamma likelihood (and so its AIC)
# assumes Gamma distributed claims, which these heavier tailed claims are
# not; the F test only relies on the variance being proportional to the
# mean squared.
nb_tests <- anova(freq_fits$F1$negbin, freq_fits$F2$negbin, freq_fits$F3$negbin)
sev_tests <- anova(sev_fits$S1, sev_fits$S2, sev_fits$S3, test = "F")
nested_tests <- list(
  frequency = list(
    list(from = "F1", to = "F2", statistic = nb_tests$`LR stat.`[2], df = nb_tests$`   df`[2], p = nb_tests$`Pr(Chi)`[2]),
    list(from = "F2", to = "F3", statistic = nb_tests$`LR stat.`[3], df = nb_tests$`   df`[3], p = nb_tests$`Pr(Chi)`[3])
  ),
  severity = list(
    list(from = "S1", to = "S2", statistic = sev_tests$F[2], df = sev_tests$Df[2], p = sev_tests$`Pr(>F)`[2]),
    list(from = "S2", to = "S3", statistic = sev_tests$F[3], df = sev_tests$Df[3], p = sev_tests$`Pr(>F)`[3])
  )
)
pick <- function(tests, first) {
  chosen <- first
  for (t in tests) if (t$from == chosen && t$p < 0.05) chosen <- t$to
  chosen
}
stopifnot(
  pick(nested_tests$frequency, "F1") == FINAL_FREQ,
  pick(nested_tests$severity, "S1") == FINAL_SEV
)

# Degrees of freedom for F3's age spline, by AIC on the training set.
age_df_search <- lapply(c(6, 8, 10, 12), function(k) {
  m <- fit_negbin(f3_rhs(k), train)
  list(df = k, aic = AIC(m))
})
stopifnot(age_df_search[[which.min(vapply(age_df_search, `[[`, 0, "aic"))]]$df == F3_AGE_DF)

# A single Tweedie GLM on cost per policy year, as an alternative to the
# frequency-severity split. The variance power is fixed at 1.6.
tweedie_model <- glm(
  as.formula(paste("I(Charges / Exposure) ~", FREQ_CANDIDATES[[FINAL_FREQ]])),
  data = train, weights = Exposure,
  family = tweedie(var.power = 1.6, link.power = 0),
  control = glm.control(maxit = 100)
)

pure_rate <- function(f, s) {
  predict(f, per_year(test), type = "response") * predict(s, test, type = "response")
}
pure_candidates <- list(
  list(model = "F1 x S1, linear", rate = pure_rate(freq_fits$F1$negbin, sev_fits$S1)),
  list(model = "F2 x S2, splines", rate = pure_rate(freq_fits$F2$negbin, sev_fits$S2)),
  list(model = "F3 x S2, final", rate = pure_rate(freq_fits$F3$negbin, sev_fits$S2)),
  list(model = "F3 x S3", rate = pure_rate(freq_fits$F3$negbin, sev_fits$S3)),
  list(model = "Tweedie GLM, F3 terms", rate = predict(tweedie_model, test, type = "response")),
  list(model = "True model", rate = true_frequency(test) * true_severity(test))
)
pure_comparison <- lapply(pure_candidates, function(p) {
  list(
    model = p$model,
    deviance_explained = cost_dev_explained(p$rate),
    gini = gini_cost(p$rate),
    cost_ae = sum(test$Charges) / sum(p$rate * test$Exposure)
  )
})

# --------------------------------------------------
# FINAL MODELS
# --------------------------------------------------

freq_model <- freq_fits[[FINAL_FREQ]]$negbin
poisson_model <- freq_fits[[FINAL_FREQ]]$poisson
sev_model <- sev_fits[[FINAL_SEV]]

poisson_dispersion <- pearson_dispersion(poisson_model)
sev_dispersion <- summary(sev_model)$dispersion
V_freq <- vcov(freq_model)
V_sev <- vcov(sev_model)

predict_frequency <- function(df) predict(freq_model, per_year(df), type = "response")
predict_severity <- function(df) predict(sev_model, df, type = "response")
predict_pure <- function(df) predict_frequency(df) * predict_severity(df)

# --------------------------------------------------
# HOLDOUT VALIDATION
# --------------------------------------------------

test$pred_rate <- predict_pure(test)
test$true_rate <- true_frequency(test) * true_severity(test)
test$pred_cost <- test$pred_rate * test$Exposure
test$true_cost <- test$true_rate * test$Exposure
test$pred_claims <- predict_frequency(test) * test$Exposure

lorenz_model <- lorenz(test$pred_rate, test$Exposure, test$Charges)
lorenz_true <- lorenz(test$true_rate, test$Exposure, test$Charges)

holdout <- list(
  policies = nrow(test),
  exposure = sum(test$Exposure),
  claims = sum(test$ClaimCount),
  claims_ae = sum(test$ClaimCount) / sum(test$pred_claims),
  cost_ae = sum(test$Charges) / sum(test$pred_cost),
  freq_deviance_explained = freq_dev_explained(predict_frequency(test)),
  sev_deviance_explained = sev_dev_explained(predict_severity(test_claims)),
  cost_deviance_explained = cost_dev_explained(test$pred_rate),
  gini_model = lorenz_model$gini,
  gini_true = lorenz_true$gini
)

# Actual over expected by plan and by province.
ae_by <- function(var) {
  lapply(levels(test[[var]]), function(l) {
    rows <- test[[var]] == l
    list(
      level = l,
      exposure = sum(test$Exposure[rows]),
      claims_ae = sum(test$ClaimCount[rows]) / sum(test$pred_claims[rows]),
      cost_ae = sum(test$Charges[rows]) / sum(test$pred_cost[rows])
    )
  })
}
ae_plan <- ae_by("Plan")
ae_province <- ae_by("Province")

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
# The base profile is the reference level of every factor: a 40-year-old
# woman in Gauteng on a hospital plan, non-smoker, BMI 25, no children.
# Sex is compared for severity only: its frequency effect depends on age
# through the interaction, and is shown as a curve instead.

base <- data.frame(Age = 40, BMI = 25, Sex = "female", Smoker = "no",
                   Province = "Gauteng", Plan = "Essential", Children = 0, Exposure = 1)
base <- set_levels(base)

factor_rows <- c(
  list(
    list(factor = "Smoker", level = "yes", term = "Smokeryes",
         true_freq = exp(TRUTH$freq_smoker), true_sev = exp(TRUTH$sev_smoker)),
    list(factor = "Children", level = "each child", term = "Children",
         true_freq = exp(TRUTH$freq_child), true_sev = exp(TRUTH$sev_child)),
    list(factor = "Sex", level = "male", term = "Sexmale", freq = FALSE,
         true_freq = NA, true_sev = exp(TRUTH$sev_male))
  ),
  lapply(2:length(PLANS), function(i) {
    list(factor = "Plan", level = PLANS[i], term = paste0("Plan", PLANS[i]),
         true_freq = exp(TRUTH$freq_plan[i]), true_sev = exp(TRUTH$sev_plan[i]))
  }),
  lapply(2:length(PROVINCES), function(i) {
    list(factor = "Province", level = PROVINCES[i], term = paste0("Province", PROVINCES[i]),
         true_freq = exp(TRUTH$freq_province[i]), true_sev = exp(TRUTH$sev_province[i]))
  })
)

relativity <- function(model, V, term) {
  est <- coef(model)[[term]]
  se <- sqrt(V[term, term])
  list(est = exp(est), lo = exp(est - 1.96 * se), hi = exp(est + 1.96 * se))
}

factors <- lapply(factor_rows, function(r) {
  f <- if (isFALSE(r$freq)) list(est = NA, lo = NA, hi = NA) else relativity(freq_model, V_freq, r$term)
  s <- relativity(sev_model, V_sev, r$term)
  list(
    factor = r$factor, level = r$level,
    freq = f$est, freq_lo = f$lo, freq_hi = f$hi,
    sev = s$est, sev_lo = s$lo, sev_hi = s$hi,
    true_freq = r$true_freq, true_sev = r$true_sev
  )
})
covered <- function(lo, hi, truth) !is.na(truth) & lo <= truth & truth <= hi
intervals_covered <- sum(vapply(factors, function(f) {
  covered(f$freq_lo, f$freq_hi, f$true_freq) + covered(f$sev_lo, f$sev_hi, f$true_sev)
}, 0))
intervals_total <- sum(vapply(factors, function(f) (!is.na(f$true_freq)) + 1, 0))

# --------------------------------------------------
# EXPORT FOR THE DASHBOARD
# --------------------------------------------------
# The dashboard rebuilds each model's design row from the coefficient
# names: the intercept, factor indicators, Children, and spline columns
# looked up in basis tables, with ":" marking an interaction (a product of
# columns). The basis tables hold every value the dashboard accepts (whole
# years 18 to 85, BMI 16.0 to 50.0 in steps of 0.1), so its predictions
# and standard errors match R's.

ages <- 18:85
bmis <- round(seq(16, 50, by = 0.1), 1)

grid_of <- function(var, values, sex = "female") {
  g <- base[rep(1, length(values)), ]
  g[[var]] <- values
  g$Sex <- factor(sex, levels = levels(base$Sex))
  g
}

# Columns of the model matrix that are spline basis functions of one
# variable (main effects only), tabulated on that variable's grid.
basis_table <- function(model, var, values) {
  X <- design(model, grid_of(var, values))
  cols <- grep(paste0("^ns\\(", var, ","), colnames(X), value = TRUE)
  cols <- cols[!grepl(":", cols)]
  lapply(setNames(cols, cols), function(c) unname(X[, c]))
}

export_model <- function(model, V, family, extra = list()) {
  c(
    list(
      family = family,
      formula = paste(deparse(formula(model), width.cutoff = 500), collapse = ""),
      terms = names(coef(model)),
      coef = unname(coef(model)),
      vcov = unname(V),
      age_basis = basis_table(model, "Age", ages),
      bmi_basis = basis_table(model, "BMI", bmis)
    ),
    extra
  )
}

# Fitted log relativity against the base profile along one variable, with
# its standard error, and the true log relativity.
curve <- function(var, values, sex = "female") {
  g <- grid_of(var, values, sex)
  side <- function(model, V, truth) {
    dX <- sweep(design(model, g), 2, drop(design(model, base)))
    list(
      fit = unname(drop(dX %*% coef(model))),
      se = unname(sqrt(rowSums((dX %*% V) * dX))),
      true = unname(log(truth(g)) - log(truth(base)))
    )
  }
  list(freq = side(freq_model, V_freq, true_frequency),
       sev = side(sev_model, V_sev, true_severity))
}

# --------------------------------------------------
# TARIFF
# --------------------------------------------------
# The fitted age and sex factor for women rises to the maternity peak at
# about 31, dips and rises again, and a published rate table should not
# fall with age. The tariff replaces each sex's age factor with the closest
# non-decreasing curve: a weighted isotonic regression (pool adjacent
# violators), weighted by the risk premium the training portfolio has at
# each age once the age and sex factor is taken out. Pooling preserves the
# weighted total, so the tariff collects the same premium as the risk
# premium within each sex. The difference is a cross-subsidy between ages:
# members in a pooled block pay the block's average factor.

pava <- function(y, w) {
  v <- y; wt <- w; n <- rep(1, length(y)); k <- 0
  for (i in seq_along(y)) {
    k <- k + 1
    v[k] <- y[i]; wt[k] <- w[i]; n[k] <- 1
    while (k > 1 && v[k - 1] > v[k]) {
      v[k - 1] <- (wt[k - 1] * v[k - 1] + wt[k] * v[k]) / (wt[k - 1] + wt[k])
      wt[k - 1] <- wt[k - 1] + wt[k]
      n[k - 1] <- n[k - 1] + n[k]
      k <- k - 1
    }
  }
  rep(v[1:k], n[1:k])
}

train$pred_rate <- predict_pure(train)
risk_factor <- lapply(setNames(levels(base$Sex), levels(base$Sex)), function(s) {
  a <- curve("Age", ages, s)
  exp(a$freq$fit + a$sev$fit)
})
tariff <- lapply(setNames(names(risk_factor), names(risk_factor)), function(s) {
  f <- risk_factor[[s]]
  rows <- train$Sex == s
  i <- match(train$Age[rows], ages)
  w <- vapply(seq_along(ages), function(j) {
    sum((train$Exposure[rows] * train$pred_rate[rows] / f[i])[i == j])
  }, 0)
  list(risk = f, tariff = pava(f, w), weight = w)
})
stopifnot(vapply(tariff, function(t) {
  abs(sum(t$weight * t$tariff) / sum(t$weight * t$risk) - 1) < 1e-12 && !is.unsorted(t$tariff)
}, TRUE))

tariff_ratio <- function(df) {
  out <- numeric(nrow(df))
  for (s in names(tariff)) {
    rows <- df$Sex == s
    i <- match(df$Age[rows], ages)
    out[rows] <- tariff[[s]]$tariff[i] / tariff[[s]]$risk[i]
  }
  out
}

# Cross-subsidy by age band and sex on the training portfolio: tariff
# premium over risk premium.
age_bands <- list(c(18, 24), c(25, 29), c(30, 34), c(35, 39), c(40, 44), c(45, 49),
                  c(50, 59), c(60, 69), c(70, 85))
cross_subsidy <- do.call(c, lapply(names(tariff), function(s) {
  lapply(age_bands, function(b) {
    rows <- train$Sex == s & train$Age >= b[1] & train$Age <= b[2]
    risk <- train$Exposure[rows] * train$pred_rate[rows]
    list(sex = s, band = sprintf("%d to %d", b[1], b[2]),
         share = sum(risk) / sum(train$Exposure[train$Sex == s] * train$pred_rate[train$Sex == s]),
         ratio = sum(risk * tariff_ratio(train[rows, ])) / sum(risk))
  })
}))

# Holdout distribution of the annual pure premium within each plan, used
# to place a quoted profile among members on the same plan and to set the
# risk classes. Across plans the premium mostly reflects the benefits
# bought, so a portfolio-wide ranking would say little about risk.
percentiles_by_plan <- lapply(setNames(PLANS, PLANS), function(p) {
  rate <- test$pred_rate[test$Plan == p]
  list(percentiles = unname(quantile(rate, probs = seq(0, 1, by = 0.01))), mean = mean(rate))
})

thin <- function(l, k = 200) {
  i <- unique(round(seq(1, length(l$x), length.out = k)))
  list(x = l$x[i], y = l$y[i])
}

export <- list(
  generated = format(Sys.Date()),
  provinces = PROVINCES,
  plans = PLANS,
  ranges = list(age = range(ages), bmi = range(bmis), children = c(0, 5)),
  base_profile = lapply(as.list(base[, setdiff(names(base), "Exposure")]), function(v) {
    if (is.factor(v)) as.character(v) else v
  }),
  frequency = export_model(freq_model, V_freq, "negative binomial", list(
    theta = freq_model$theta, theta_se = freq_model$SE.theta,
    theta_true = 1 / TRUTH$frailty_var, poisson_dispersion = poisson_dispersion
  )),
  severity = export_model(sev_model, V_sev, "Gamma", list(
    dispersion = sev_dispersion, dispersion_true = z_cv2()
  )),
  curves = list(
    age = list(female = curve("Age", ages, "female"), male = curve("Age", ages, "male")),
    bmi = curve("BMI", bmis)
  ),
  factors = factors,
  tariff = c(
    list(ages = ages),
    lapply(tariff, function(t) list(risk = t$risk, tariff = t$tariff)),
    list(cross_subsidy = cross_subsidy)
  ),
  portfolio = percentiles_by_plan,
  comparison = list(
    frequency = freq_comparison,
    severity = sev_comparison,
    pure = pure_comparison,
    nested_tests = nested_tests,
    age_df_search = age_df_search,
    final = list(frequency = FINAL_FREQ, severity = FINAL_SEV)
  ),
  validation = list(
    train_policies = nrow(train),
    train_exposure = sum(train$Exposure),
    train_claims = sum(train$ClaimCount),
    holdout = holdout,
    ae_plan = ae_plan,
    ae_province = ae_province,
    lift = lift,
    lorenz_model = thin(lorenz_model),
    lorenz_true = thin(lorenz_true),
    intervals_covered = intervals_covered,
    intervals_total = intervals_total
  )
)

dir.create("dashboard/src", recursive = TRUE, showWarnings = FALSE)
dir.create("dashboard/test", recursive = TRUE, showWarnings = FALSE)
write_json(export, "dashboard/src/model.json", auto_unbox = TRUE, digits = NA, na = "null")

# R predictions and standard errors on random profiles, for the
# dashboard's parity test.
set.seed(7)
k <- 300
cases <- data.frame(
  Age = sample(ages, k, replace = TRUE),
  BMI = sample(bmis, k, replace = TRUE),
  Sex = sample(levels(insurance_data$Sex), k, replace = TRUE),
  Smoker = sample(levels(insurance_data$Smoker), k, replace = TRUE),
  Province = sample(PROVINCES, k, replace = TRUE),
  Plan = sample(PLANS, k, replace = TRUE),
  Children = sample(0:5, k, replace = TRUE),
  Exposure = 1
)
lf <- predict_log(freq_model, cases, V_freq)
ls <- predict_log(sev_model, cases, V_sev)
cases$frequency <- predict_frequency(cases)
cases$severity <- predict_severity(cases)
cases$pure <- cases$frequency * cases$severity
cases$se_frequency <- lf$se
cases$se_severity <- ls$se
cases$tariff <- cases$pure * tariff_ratio(cases)
cases$Exposure <- NULL
stopifnot(max(abs(exp(lf$fit + ls$fit) / cases$pure - 1)) < 1e-12)
write_json(cases, "dashboard/test/parity-cases.json", digits = NA)

# --------------------------------------------------
# SAVE MODELS
# --------------------------------------------------
# Drop the training data and per-row fitted values; prediction only needs
# the formula, the spline knots and the coefficients. The covariance
# matrix is kept as $V, because vcov() needs the QR decomposition dropped
# here.

strip <- function(m, V) {
  m[c("data", "model", "y", "residuals", "fitted.values", "effects", "weights",
      "prior.weights", "linear.predictors", "offset")] <- NULL
  m$qr <- list(pivot = m$qr$pivot, rank = m$qr$rank)
  class(m$qr) <- "qr"
  m$V <- V
  attr(m$terms, ".Environment") <- globalenv()
  m
}
dir.create("models", showWarnings = FALSE)
saveRDS(strip(freq_model, V_freq), "models/freq_model.rds")
saveRDS(strip(sev_model, V_sev), "models/sev_model.rds")
saveRDS(lapply(percentiles_by_plan, `[[`, "percentiles"), "models/portfolio_percentiles.rds")
saveRDS(do.call(rbind, lapply(names(tariff), function(s) {
  data.frame(Age = ages, Sex = s, risk = tariff[[s]]$risk, tariff = tariff[[s]]$tariff)
})), "models/tariff.rds")

# --------------------------------------------------
# VALIDATION REPORT
# --------------------------------------------------

fmt <- function(x, d = 3) ifelse(is.na(x), "", formatC(x, format = "f", digits = d, big.mark = ","))
fmt_p <- function(p) if (p < 0.001) "< 0.001" else fmt(p)
pct <- function(x) paste0(fmt(100 * x, 1), "%")
row <- function(...) paste("|", paste(..., sep = " | "), "|")

# Coverage tables from scripts/coverage_study.R, when it has been run.
coverage_lines <- if (file.exists("dashboard/src/coverage.json")) {
  cov <- fromJSON("dashboard/src/coverage.json", simplifyVector = FALSE)
  premium <- Filter(function(m) startsWith(m$model, "Premium, negative binomial"), cov$models)[[1]]
  c("## Interval coverage", "",
    sprintf(paste(
      "From `scripts/coverage_study.R`: %d portfolios of %s policies simulated from the true",
      "model and refitted, counting how often the 95%% intervals contain the true value (Monte",
      "Carlo standard error %s points). SE ratio is the mean standard error over the spread of",
      "the estimates; 1 means the standard errors are the right size. Details in",
      "`reports/coverage.md`."), cov$reps, format(cov$policies, big.mark = ","), fmt(100 * cov$monte_carlo_se, 1)),
    "",
    "| Intervals | Coverage | Mean SE ratio |",
    "| --- | --- | --- |",
    vapply(cov$models, function(m) row(m$model, pct(m$overall$coverage), fmt(m$overall$se_ratio, 2)), ""),
    "",
    "Premium intervals (negative binomial x Gamma) for six fixed profiles:",
    "",
    "| Profile | Coverage | Bias (log) |",
    "| --- | --- | --- |",
    vapply(premium$rows, function(r) row(r$target, pct(r$coverage), fmt(r$bias, 4)), ""),
    "")
} else character(0)

lines <- c(
  "# Validation results",
  "",
  "Written by `scripts/model_training.R`. The models are fitted on a random 80% of the",
  "synthetic portfolio and checked on the remaining 20%. Because the data is synthetic,",
  "the fitted effects can also be compared with the true parameters in `scripts/simulate.R`.",
  "",
  "## Model comparison",
  "",
  "Candidate rating structures. Every candidate also includes Smoker, Children, Province",
  "and Plan.",
  "",
  "| Name | Age, BMI and sex terms |",
  "| --- | --- |",
  row("F1, S1", "linear Age and BMI, Sex"),
  row("F2, S2", "ns(Age, 4), ns(BMI, 4), Sex"),
  row("F3", sprintf("ns(Age, %d) x Sex interaction, ns(BMI, 4)", F3_AGE_DF)),
  row("S3", "ns(Age, 4) x Sex interaction, ns(BMI, 4)"),
  "",
  "### Frequency",
  "",
  "Training AIC, and holdout Poisson deviance explained and Gini of claim counts.",
  "",
  "| Model | Family | Parameters | AIC | Deviance explained | Gini |",
  "| --- | --- | --- | --- | --- | --- |",
  vapply(freq_comparison, function(r) row(r$model, r$family, r$parameters, fmt(r$aic, 0),
                                          pct(r$deviance_explained), fmt(r$gini)), ""),
  "",
  sprintf(paste(
    "The Poisson %s model has a Pearson dispersion of %s, so the claim counts are",
    "overdispersed and Poisson standard errors are too small. The negative binomial",
    "estimates theta = %s (standard error %s), against a true value of %s."),
    FINAL_FREQ, fmt(poisson_dispersion), fmt(freq_model$theta), fmt(freq_model$SE.theta),
    fmt(1 / TRUTH$frailty_var)),
  "",
  "### Severity",
  "",
  "Gamma GLMs. Training AIC and dispersion, and holdout Gamma deviance explained and Gini",
  "of claim cost by predicted cost per claim.",
  "",
  "| Model | Parameters | AIC | Dispersion | Deviance explained | Gini |",
  "| --- | --- | --- | --- | --- | --- |",
  vapply(sev_comparison, function(r) row(r$model, r$parameters, fmt(r$aic, 0), fmt(r$dispersion),
                                         pct(r$deviance_explained), fmt(r$gini)), ""),
  "",
  "### Selection",
  "",
  "Nested tests on the training set, adding terms only at the 5% level: likelihood ratio",
  "tests for the negative binomial models, and F tests with the estimated dispersion for the",
  "Gamma models (the Gamma AIC assumes Gamma distributed claims, which these are not).",
  "",
  "| Test | Statistic | df | p-value |",
  "| --- | --- | --- | --- |",
  vapply(nested_tests$frequency, function(t) row(paste(t$from, "to", t$to, "(LR)"), fmt(t$statistic, 1), t$df, fmt_p(t$p)), ""),
  vapply(nested_tests$severity, function(t) row(paste(t$from, "to", t$to, "(F)"), fmt(t$statistic, 2), t$df, fmt_p(t$p)), ""),
  "",
  sprintf(paste(
    "The degrees of freedom of F3's age spline are chosen by AIC (negative binomial, training",
    "set): %s. A first version with 6 degrees of freedom smoothed away the maternity peak in",
    "women's claim frequency, and the coverage study showed it: premium intervals for women aged",
    "31 and 40 contained the true value only 77%% to 80%% of the time."),
    paste(vapply(age_df_search, function(a) sprintf("%d df %s", a$df, fmt(a$aic, 1)), ""), collapse = ", ")),
  "",
  sprintf("Final models: %s negative binomial for frequency and %s Gamma for severity.", FINAL_FREQ, FINAL_SEV),
  "",
  "### Pure premium",
  "",
  "Holdout cost per policy year. Deviance explained uses the Tweedie deviance with power 1.6.",
  "",
  "| Model | Deviance explained | Gini | Actual over expected |",
  "| --- | --- | --- | --- |",
  vapply(pure_comparison, function(r) row(r$model, pct(r$deviance_explained), fmt(r$gini), fmt(r$cost_ae)), ""),
  "",
  "## Fit",
  "",
  sprintf("- Training set: %s policies, %s policy years, %s claims.", fmt(nrow(train), 0),
          fmt(sum(train$Exposure), 0), fmt(sum(train$ClaimCount), 0)),
  sprintf("- Severity Gamma dispersion: %s, against a true squared coefficient of variation per claim of %s.",
          fmt(sev_dispersion), fmt(z_cv2())),
  "",
  "## Holdout",
  "",
  sprintf("- Holdout set: %s policies, %s policy years, %s claims.",
          fmt(holdout$policies, 0), fmt(holdout$exposure, 0), fmt(holdout$claims, 0)),
  sprintf("- Actual over expected claim count: %s.", fmt(holdout$claims_ae)),
  sprintf("- Actual over expected claim cost: %s.", fmt(holdout$cost_ae)),
  sprintf("- Deviance explained: frequency %s, severity %s, cost per policy year %s.",
          pct(holdout$freq_deviance_explained), pct(holdout$sev_deviance_explained),
          pct(holdout$cost_deviance_explained)),
  sprintf("- Gini of the pure premium: %s, against %s for the true generating model.",
          fmt(holdout$gini_model), fmt(holdout$gini_true)),
  "",
  "### Actual over expected by plan and province",
  "",
  "| Group | Policy years | Claims | Cost |",
  "| --- | --- | --- | --- |",
  vapply(c(ae_plan, ae_province), function(a) row(a$level, fmt(a$exposure, 0), fmt(a$claims_ae), fmt(a$cost_ae)), ""),
  "",
  "## Lift by predicted cost band",
  "",
  "Ten bands of equal exposure, from lowest to highest predicted cost per policy year.",
  "",
  "| Band | Policies | Predicted | Actual | True expected |",
  "| --- | --- | --- | --- | --- |",
  vapply(lift, function(l) row(l$band, fmt(l$policies, 0), fmt(l$predicted, 0),
                               fmt(l$actual, 0), fmt(l$true, 0)), ""),
  "",
  "## Tariff and cross-subsidy",
  "",
  "The tariff replaces each sex's fitted age factor with the closest curve that never falls",
  "with age (weighted isotonic regression, weighted by the training portfolio's risk premium",
  "at each age), so it collects the same total premium as the risk premium within each sex.",
  "Ratio is tariff premium over risk premium on the training portfolio: above 1, the band pays",
  "more than its expected claims and subsidises the others.",
  "",
  "| Sex | Age band | Share of risk premium | Tariff over risk |",
  "| --- | --- | --- | --- |",
  vapply(cross_subsidy, function(c) row(c$sex, c$band, pct(c$share), fmt(c$ratio)), ""),
  "",
  "## Relativities against the true parameters",
  "",
  "Multiplicative effect on the base profile, with 95% Wald intervals. Sex is compared for",
  "severity only, because its frequency effect depends on age.",
  sprintf("%d of %d intervals contain the true value.", intervals_covered, intervals_total),
  "",
  "| Factor | Level | Frequency [95% CI] | True | Severity [95% CI] | True |",
  "| --- | --- | --- | --- | --- | --- |",
  vapply(factors, function(f) {
    fr <- if (is.na(f$freq)) "" else sprintf("%s [%s, %s]", fmt(f$freq), fmt(f$freq_lo), fmt(f$freq_hi))
    row(f$factor, f$level, fr, fmt(f$true_freq),
        sprintf("%s [%s, %s]", fmt(f$sev), fmt(f$sev_lo), fmt(f$sev_hi)), fmt(f$true_sev))
  }, ""),
  "",
  coverage_lines
)
writeLines(lines, "reports/validation.md")
cat(lines, sep = "\n")
