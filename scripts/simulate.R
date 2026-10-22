# --------------------------------------------------
# Synthetic South African health insurance portfolio
# --------------------------------------------------
# simulate_portfolio() generates one portfolio of principal members with
# their dependent children, and true_frequency() / true_severity() return
# the expected claims per policy year and expected cost per claim under the
# parameters below. The data generation script, the model training script
# and the coverage study all use this file, so the parameters live in one
# place.
#
# The product is generic health insurance with three benefit tiers, and the
# provinces give the portfolio a South African geography. The parameters are
# illustrative assumptions, not estimated from real data.
# --------------------------------------------------

PROVINCES <- c(
  "Gauteng", "Western Cape", "KwaZulu-Natal", "Eastern Cape", "Free State",
  "Limpopo", "Mpumalanga", "North West", "Northern Cape"
)
# Benefit tiers by scope of cover. Essential covers in-hospital treatment;
# Standard adds out-of-hospital specialists, scans and tests; Comprehensive
# adds GP visits, prescribed medicines, dental and optical.
PLANS <- c("Essential", "Standard", "Comprehensive")

TRUTH <- list(
  # Membership is concentrated in the metros, so the province mix is far
  # from the population mix.
  province_share = c(0.38, 0.17, 0.15, 0.07, 0.05, 0.05, 0.06, 0.05, 0.02),

  # Claim frequency, per policy year, on the log scale. The base is a
  # 40-year-old woman in Gauteng on the Essential plan, non-smoker, BMI 25,
  # no children.
  freq_base = log(0.30),
  freq_age = 0.025,              # per year of age
  freq_age_old = 0.0006,         # per squared year above 55
  freq_maternity = 0.45,         # peak extra log rate for women, at age 31
  freq_bmi_high = 0.035,         # per BMI point above 25
  freq_bmi_low = 0.05,           # per BMI point below 20
  freq_smoker = 0.26,
  freq_child = 0.22,             # per dependent child
  freq_province = c(0, -0.03, -0.05, -0.10, -0.08, -0.15, -0.10, -0.10, -0.12),
  freq_plan = c(0, log(4), log(10)),  # out-of-hospital cover means many more, smaller claims
  frailty_var = 0.3,             # gamma frailty: negative binomial with theta = 1 / 0.3

  # Claim severity, per claim, on the log scale.
  sev_base_mean = 45000,         # expected cost per claim for the base profile
  sev_age = 0.008,
  sev_bmi_high = 0.015,
  sev_smoker = 0.22,
  sev_child = log(0.93),         # children's claims are smaller
  sev_male = log(1.05),
  sev_province = c(0, 0.02, -0.04, -0.08, -0.07, -0.10, -0.06, -0.08, -0.09),
  sev_plan = c(0, log(0.45), log(0.25)),

  # Each claim is exp(severity scale) times Z, where Z is lognormal with
  # probability 0.97 and a Pareto large claim with probability 0.03.
  sev_sdlog = 1.1,
  large_prob = 0.03,
  large_scale = 6,
  large_alpha = 2.3
)

# Mean of Z, so the severity scale can be set to give the base mean above.
z_mean <- function(t = TRUTH) {
  (1 - t$large_prob) * exp(t$sev_sdlog^2 / 2) +
    t$large_prob * t$large_scale * t$large_alpha / (t$large_alpha - 1)
}

# Squared coefficient of variation of a single claim, the Gamma GLM's
# true dispersion.
z_cv2 <- function(t = TRUTH) {
  p <- t$large_prob
  a <- t$large_alpha
  m2_ln <- exp(2 * t$sev_sdlog^2)
  m2_large <- t$large_scale^2 * a / (a - 2)
  m2 <- (1 - p) * m2_ln + p * m2_large
  m2 / z_mean(t)^2 - 1
}

freq_log_rate <- function(df, t = TRUTH) {
  female <- df$Sex == "female"
  t$freq_base +
    t$freq_age * (df$Age - 40) +
    t$freq_age_old * pmax(df$Age - 55, 0)^2 +
    t$freq_maternity * female * exp(-((df$Age - 31) / 6)^2) -
    t$freq_maternity * exp(-((40 - 31) / 6)^2) +  # keeps the base profile at freq_base
    t$freq_bmi_high * pmax(df$BMI - 25, 0) +
    t$freq_bmi_low * pmax(20 - df$BMI, 0) +
    t$freq_smoker * (df$Smoker == "yes") +
    t$freq_child * df$Children +
    t$freq_province[match(df$Province, PROVINCES)] +
    t$freq_plan[match(df$Plan, PLANS)]
}

sev_log_mean <- function(df, t = TRUTH) {
  log(t$sev_base_mean) +
    t$sev_age * (df$Age - 40) +
    t$sev_bmi_high * pmax(df$BMI - 25, 0) +
    t$sev_smoker * (df$Smoker == "yes") +
    t$sev_child * df$Children +
    t$sev_male * (df$Sex == "male") +
    t$sev_province[match(df$Province, PROVINCES)] +
    t$sev_plan[match(df$Plan, PLANS)]
}

true_frequency <- function(df, t = TRUTH) exp(freq_log_rate(df, t))
true_severity <- function(df, t = TRUTH) exp(sev_log_mean(df, t))

simulate_portfolio <- function(n = 1e5, seed = 123, t = TRUTH) {
  set.seed(seed)

  # Principal members: working-age heavy, thinning out after 60.
  Age <- 18 + round(67 * rbeta(n, 2.0, 2.8))
  Sex <- sample(c("female", "male"), n, replace = TRUE, prob = c(0.52, 0.48))
  Province <- sample(PROVINCES, n, replace = TRUE, prob = t$province_share)

  # Dependent children peak for members around 40.
  Children <- pmin(rpois(n, 1.8 * exp(-((Age - 40) / 11)^2)), 5)

  # Smoking is more common in men and falls with age.
  Smoker <- ifelse(
    runif(n) < plogis(-1.9 + 1.2 * (Sex == "male") - 0.015 * (Age - 40)),
    "yes", "no"
  )

  # BMI: higher for women, rising with age to 60, slightly lower for smokers.
  BMI <- rlnorm(
    n,
    meanlog = log(26) + 0.07 * (Sex == "female") + 0.004 * (pmin(Age, 60) - 40) -
      0.04 * (Smoker == "yes"),
    sdlog = 0.17
  )
  BMI <- round(pmin(pmax(BMI, 16), 50), 1)

  # Plan choice: older members buy richer cover, families lean to Standard.
  u <- cbind(
    0,
    0.2 + 0.25 * (Children > 0),
    -0.9 + 0.035 * (Age - 40) - 0.3 * (Smoker == "yes")
  )
  p <- exp(u) / rowSums(exp(u))
  r <- runif(n)
  Plan <- PLANS[1 + (r > p[, 1]) + (r > p[, 1] + p[, 2])]

  # Exposure: most members are covered all year, the rest join or leave.
  Exposure <- ifelse(runif(n) < 0.8, 1, round(runif(n, 0.1, 1), 2))

  df <- data.frame(Age, Sex, BMI, Smoker, Province, Plan, Children, Exposure)

  # Claim counts: Poisson given a gamma frailty, so negative binomial overall.
  frailty <- rgamma(n, shape = 1 / t$frailty_var, scale = t$frailty_var)
  df$ClaimCount <- rpois(n, true_frequency(df, t) * df$Exposure * frailty)

  # Every claim has its own cost; a policy's charges are the sum.
  claim_policy <- rep(seq_len(n), df$ClaimCount)
  k <- length(claim_policy)
  large <- runif(k) < t$large_prob
  z <- ifelse(
    large,
    t$large_scale * runif(k)^(-1 / t$large_alpha),
    rlnorm(k, 0, t$sev_sdlog)
  )
  scale <- exp(sev_log_mean(df, t)[claim_policy]) / z_mean(t)
  df$Charges <- 0
  if (k > 0) df$Charges[unique(claim_policy)] <- rowsum(scale * z, claim_policy)[, 1]
  df$Charges <- round(df$Charges, 2)
  df
}

# Factor levels used by every model, with the base profile's level first.
set_levels <- function(df) {
  df$Sex <- factor(df$Sex, levels = c("female", "male"))
  df$Smoker <- factor(df$Smoker, levels = c("no", "yes"))
  df$Province <- factor(df$Province, levels = PROVINCES)
  df$Plan <- factor(df$Plan, levels = PLANS)
  df
}
