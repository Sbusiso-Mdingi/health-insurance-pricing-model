# --------------------------------------------------
# Model definitions shared by training and the coverage study
# --------------------------------------------------
# The candidate rating structures, the final frequency and severity models,
# and the helpers that fit them. The final choice is made in
# scripts/model_training.R by nested tests and is recorded here so the
# coverage study refits exactly the same models.
# --------------------------------------------------

suppressPackageStartupMessages({
  library(splines)
  library(MASS)
})

RATING <- "Smoker + Children + Province + Plan"

# Degrees of freedom of the age spline in F3, chosen by AIC in
# scripts/model_training.R. Women's frequency has a maternity peak around
# age 31, and with 6 degrees of freedom the spline smoothed it away: the
# first coverage study found premium intervals for women aged 31 and 40
# covering only 77% to 80% of the time.
F3_AGE_DF <- 10
f3_rhs <- function(k) paste0("ns(Age, df = ", k, ") * Sex + ns(BMI, df = 4) + ", RATING)

FREQ_CANDIDATES <- list(
  F1 = paste("Age + BMI + Sex +", RATING),
  F2 = paste("ns(Age, df = 4) + ns(BMI, df = 4) + Sex +", RATING),
  F3 = f3_rhs(F3_AGE_DF)
)
SEV_CANDIDATES <- list(
  S1 = paste("Age + BMI + Sex +", RATING),
  S2 = paste("ns(Age, df = 4) + ns(BMI, df = 4) + Sex +", RATING),
  S3 = paste("ns(Age, df = 4) * Sex + ns(BMI, df = 4) +", RATING)
)

FINAL_FREQ <- "F3"
FINAL_SEV <- "S2"

freq_formula <- function(rhs) as.formula(paste("ClaimCount ~", rhs, "+ offset(log(Exposure))"))
sev_formula <- function(rhs) as.formula(paste("AvgCost ~", rhs))

# Frequency: claims per policy year, with log exposure as an offset.
fit_poisson <- function(rhs, data) glm(freq_formula(rhs), data = data, family = poisson(link = "log"))
fit_negbin <- function(rhs, data) glm.nb(freq_formula(rhs), data = data)

# Severity: average cost per claim on policies with claims, weighted by
# the claim count. The variance of an average of k claims is the per-claim
# variance divided by k, so this is equivalent to fitting every claim.
claims_only <- function(data) {
  d <- data[data$ClaimCount > 0, ]
  d$AvgCost <- d$Charges / d$ClaimCount
  d
}
fit_gamma <- function(rhs, data) {
  glm(sev_formula(rhs), data = claims_only(data), family = Gamma(link = "log"),
      weights = ClaimCount)
}

pearson_dispersion <- function(m) sum(residuals(m, type = "pearson")^2) / m$df.residual

# Design matrix for new profiles, using the fitted spline knots and levels.
design <- function(model, newdata) {
  tt <- delete.response(terms(model))
  mf <- model.frame(tt, newdata, xlev = model$xlevels)
  model.matrix(tt, mf, contrasts.arg = model$contrasts)
}

# Log-scale prediction per policy year and its standard error, from the
# coefficient covariance matrix (the delta method on the log link).
predict_log <- function(model, newdata, V = vcov(model)) {
  X <- design(model, newdata)
  b <- coef(model)
  list(fit = drop(X %*% b), se = sqrt(rowSums((X %*% V) * X)))
}
