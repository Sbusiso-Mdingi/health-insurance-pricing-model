# --------------------------------------------------
# Synthetic Health Insurance Data Generation
# --------------------------------------------------
# This script generates a fully synthetic health insurance portfolio
# suitable for frequency-severity pricing models. The true parameters
# are written down here so the fitted models can be checked against them.
#
# All data is artificial and created for demonstration purposes only.
# --------------------------------------------------

set.seed(123)

library(dplyr)
library(splines)

# --------------------------------------------------
# PARAMETERS
# --------------------------------------------------
n <- 100000

# --------------------------------------------------
# DEMOGRAPHICS
# --------------------------------------------------

Age <- round(runif(n, min = 18, max = 85))

Sex <- sample(c("male", "female"), n, replace = TRUE, prob = c(0.48, 0.52))

Region <- sample(
  c("southeast", "southwest", "northeast", "northwest"),
  n,
  replace = TRUE,
  prob = c(0.35, 0.25, 0.20, 0.20)
)

Children <- rpois(n, lambda = pmin(Age / 30, 2))
Children <- pmin(Children, 5)

# Exposure in policy years: most policies are in force all year, the
# rest joined or left part way through.
Exposure <- ifelse(runif(n) < 0.8, 1, round(runif(n, 0.1, 1), 2))

# --------------------------------------------------
# BEHAVIOURAL RISK FACTORS
# --------------------------------------------------

# Smoking probability increases with age
p_smoker <- plogis(-3 + 0.04 * Age)
Smoker <- rbinom(n, 1, p_smoker)
Smoker <- factor(ifelse(Smoker == 1, "yes", "no"))

# BMI: lognormal with demographic effects
mu_bmi <- log(25) +
  0.002 * (Age - 40) +
  ifelse(Sex == "male", 0.03, 0) +
  ifelse(Smoker == "yes", 0.08, 0)

BMI <- rlnorm(n, meanlog = mu_bmi, sdlog = 0.15)
BMI <- pmin(pmax(BMI, 18), 45)

# --------------------------------------------------
# CLAIM FREQUENCY (Poisson, per policy year)
# --------------------------------------------------
# Sex has no true effect on frequency.

lambda <- exp(
  -2.5 +
    0.015 * Age +
    0.03 * (BMI - 25) +
    0.6 * (Smoker == "yes") +
    0.08 * Children +
    ifelse(Region == "southeast", 0.2, 0)
)

ClaimCount <- rpois(n, lambda * Exposure)

# --------------------------------------------------
# CLAIM SEVERITY (Lognormal, per claim)
# --------------------------------------------------
# Sex and Region have no true effect on severity.

mu_sev <- 8.0 +
  0.01 * Age +
  0.02 * (BMI - 25) +
  0.5 * (Smoker == "yes") +
  0.1 * Children

sigma_sev <- 0.8

# Each claim gets its own independent severity draw, and a policy's
# charges are the sum over its claims.
claim_policy <- rep(seq_len(n), ClaimCount)
claim_cost <- rlnorm(length(claim_policy), meanlog = mu_sev[claim_policy], sdlog = sigma_sev)
TotalCharges <- numeric(n)
TotalCharges[unique(claim_policy)] <- rowsum(claim_cost, claim_policy)[, 1]

# --------------------------------------------------
# FINAL DATASET
# --------------------------------------------------

insurance_data <- data.frame(
  Age = Age,
  Sex = factor(Sex),
  BMI = round(BMI, 1),
  Smoker = Smoker,
  Region = factor(Region),
  Children = Children,
  Exposure = Exposure,
  ClaimCount = ClaimCount,
  Charges = round(TotalCharges, 2)
)

# --------------------------------------------------
# SUMMARY CHECKS
# --------------------------------------------------

summary(insurance_data)
sum(insurance_data$ClaimCount) / sum(insurance_data$Exposure)
sum(insurance_data$Charges) / sum(insurance_data$ClaimCount)

# --------------------------------------------------
# SAVE DATA
# --------------------------------------------------

write.csv(insurance_data, "data/synthetic_health_insurance_data.csv", row.names = FALSE)

# --------------------------------------------------
# END OF SCRIPT
# --------------------------------------------------
