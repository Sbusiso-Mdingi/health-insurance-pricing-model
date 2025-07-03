# --------------------------------------------------
# Synthetic Health Insurance Data Generation
# --------------------------------------------------
# This script generates a fully synthetic health insurance portfolio
# suitable for frequency–severity pricing models.
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
# CLAIM FREQUENCY (Poisson)
# --------------------------------------------------

lambda <- exp(
  -2.5 +
    0.015 * Age +
    0.03 * (BMI - 25) +
    0.6 * (Smoker == "yes") +
    0.08 * Children +
    ifelse(Region == "southeast", 0.2, 0)
)

ClaimCount <- rpois(n, lambda)

# --------------------------------------------------
# CLAIM SEVERITY (Lognormal)
# --------------------------------------------------

mu_sev <- 8.0 +
  0.01 * Age +
  0.02 * (BMI - 25) +
  0.5 * (Smoker == "yes") +
  0.1 * Children

sigma_sev <- 0.8

TotalCharges <- ifelse(
  ClaimCount > 0,
  rlnorm(n, meanlog = mu_sev, sdlog = sigma_sev) * ClaimCount,
  0
)

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
  ClaimCount = ClaimCount,
  Charges = round(TotalCharges, 2)
)

# --------------------------------------------------
# SUMMARY CHECKS
# --------------------------------------------------

summary(insurance_data)
mean(insurance_data$ClaimCount)
mean(insurance_data$Charges[insurance_data$Charges > 0])

# --------------------------------------------------
# SAVE DATA
# --------------------------------------------------

write.csv(insurance_data, "data/synthetic_health_insurance_data.csv", row.names = FALSE)

# --------------------------------------------------
# END OF SCRIPT
# --------------------------------------------------
