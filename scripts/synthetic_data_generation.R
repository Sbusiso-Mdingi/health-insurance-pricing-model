# --------------------------------------------------
# Synthetic Health Insurance Data Generation
# --------------------------------------------------
# Generates the synthetic South African portfolio used by the pricing
# models. The simulation itself, and its true parameters, are in
# scripts/simulate.R.
#
# All data is artificial and created for demonstration purposes only.
#
# Run from the project root: Rscript scripts/synthetic_data_generation.R
# --------------------------------------------------

source("scripts/simulate.R")

insurance_data <- simulate_portfolio(n = 1e5, seed = 123)

# --------------------------------------------------
# SUMMARY CHECKS
# --------------------------------------------------

summary(set_levels(insurance_data))

cat("\nClaims per policy year:", sum(insurance_data$ClaimCount) / sum(insurance_data$Exposure), "\n")
cat("Cost per claim:", sum(insurance_data$Charges) / sum(insurance_data$ClaimCount), "\n")
cat("Cost per policy year:", sum(insurance_data$Charges) / sum(insurance_data$Exposure), "\n\n")

by_plan <- split(insurance_data, insurance_data$Plan)
print(t(sapply(by_plan, function(d) c(
  share = nrow(d) / nrow(insurance_data),
  claims_per_year = sum(d$ClaimCount) / sum(d$Exposure),
  cost_per_claim = sum(d$Charges) / sum(d$ClaimCount),
  monthly_cost = sum(d$Charges) / sum(d$Exposure) / 12
))))
cat("\nSmokers by sex:\n")
print(prop.table(table(insurance_data$Sex, insurance_data$Smoker), 1))

# --------------------------------------------------
# SAVE DATA
# --------------------------------------------------

write.csv(insurance_data, "data/synthetic_health_insurance_data.csv", row.names = FALSE)
