# --------------------------------------------------
# Coverage study for the 95% intervals
# --------------------------------------------------
# Simulates 200 portfolios from the true model, refits the final models on
# each, and records how often the 95% Wald intervals contain the true
# value: for the relativities, and for the expected annual cost of six
# fixed profiles (the premium interval shown in the calculator). The
# Poisson version of the final frequency model is refitted too, to show
# what ignoring overdispersion does to its intervals.
#
# Each portfolio has 80,000 policies, about the size of the training set.
#
# Outputs:
#   reports/coverage.md                 coverage tables
#   reports/coverage_estimates.csv      every estimate and standard error
#   dashboard/src/coverage.json         coverage tables for the dashboard
#
# Run from the project root: Rscript scripts/coverage_study.R
# Takes about 5 minutes on 7 cores.
# --------------------------------------------------

suppressPackageStartupMessages({
  library(parallel)
  library(jsonlite)
})
source("scripts/simulate.R")
source("scripts/models.R")

REPS <- as.integer(Sys.getenv("COVERAGE_REPS", "200"))
N_POLICIES <- 8e4
CORES <- max(1, detectCores() - 1)

coef_targets <- rbind(
  data.frame(term = "Smokeryes", label = "Smoker",
             freq = TRUTH$freq_smoker, sev = TRUTH$sev_smoker),
  data.frame(term = "Children", label = "Each child",
             freq = TRUTH$freq_child, sev = TRUTH$sev_child),
  data.frame(term = "Sexmale", label = "Male", freq = NA, sev = TRUTH$sev_male),
  data.frame(term = paste0("Plan", PLANS[-1]), label = paste(PLANS[-1], "plan"),
             freq = TRUTH$freq_plan[-1], sev = TRUTH$sev_plan[-1]),
  data.frame(term = paste0("Province", PROVINCES[-1]), label = PROVINCES[-1],
             freq = TRUTH$freq_province[-1], sev = TRUTH$sev_province[-1])
)

profiles <- set_levels(data.frame(
  label = c(
    "Base: woman, 40, Gauteng, Essential",
    "Man, 30, smoker, Western Cape, Standard",
    "Woman, 31, 2 children, KwaZulu-Natal, Standard",
    "Woman, 62, BMI 32, Gauteng, Comprehensive",
    "Man, 50, 1 child, Limpopo, Comprehensive",
    "Man, 78, smoker, BMI 30, Northern Cape, Essential"
  ),
  Age = c(40, 30, 31, 62, 50, 78),
  Sex = c("female", "male", "female", "female", "male", "male"),
  BMI = c(25, 24, 27, 32, 28, 30),
  Smoker = c("no", "yes", "no", "no", "no", "yes"),
  Province = c("Gauteng", "Western Cape", "KwaZulu-Natal", "Gauteng", "Limpopo", "Northern Cape"),
  Plan = c("Essential", "Standard", "Standard", "Comprehensive", "Comprehensive", "Essential"),
  Children = c(0, 0, 2, 0, 1, 0),
  Exposure = 1
))
profiles$true_log <- log(true_frequency(profiles) * true_severity(profiles))

one_rep <- function(r) {
  d <- set_levels(simulate_portfolio(N_POLICIES, seed = 1000 + r))
  nb <- fit_negbin(FREQ_CANDIDATES[[FINAL_FREQ]], d)
  po <- fit_poisson(FREQ_CANDIDATES[[FINAL_FREQ]], d)
  ga <- fit_gamma(SEV_CANDIDATES[[FINAL_SEV]], d)

  coefs <- function(m, model, truth) {
    keep <- !is.na(truth)
    t <- coef_targets$term[keep]
    data.frame(rep = r, model = model, target = coef_targets$label[keep],
               est = unname(coef(m)[t]), se = unname(sqrt(diag(vcov(m))[t])),
               truth = truth[keep])
  }
  prem <- function(f, model) {
    pf <- predict_log(f, profiles)
    ps <- predict_log(ga, profiles)
    data.frame(rep = r, model = model, target = profiles$label,
               est = pf$fit + ps$fit, se = sqrt(pf$se^2 + ps$se^2),
               truth = profiles$true_log)
  }
  rbind(
    coefs(nb, "Frequency, negative binomial", coef_targets$freq),
    coefs(po, "Frequency, Poisson", coef_targets$freq),
    coefs(ga, "Severity, Gamma", coef_targets$sev),
    prem(nb, "Premium, negative binomial x Gamma"),
    prem(po, "Premium, Poisson x Gamma")
  )
}

t0 <- Sys.time()
results <- do.call(rbind, mclapply(seq_len(REPS), one_rep, mc.cores = CORES, mc.set.seed = FALSE))
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
stopifnot(length(unique(results$rep)) == REPS)
results$covered <- abs(results$est - results$truth) <= qnorm(0.975) * results$se

dir.create("reports", showWarnings = FALSE)
write.csv(results, "reports/coverage_estimates.csv", row.names = FALSE)

# Coverage, and the mean standard error over the standard deviation of the
# estimates across portfolios (1 when the standard errors are right).
summarise <- function(rows) {
  list(
    coverage = mean(rows$covered),
    se_ratio = mean(rows$se) / sd(rows$est),
    bias = mean(rows$est - rows$truth)
  )
}
by_model <- split(results, factor(results$model, levels = unique(results$model)))
tables <- lapply(by_model, function(m) {
  rows <- lapply(unique(m$target), function(t) c(list(target = t), summarise(m[m$target == t, ])))
  # Overall: coverage over every interval, and the mean of the per-target
  # SE ratios (the estimates of different targets cannot be pooled).
  list(
    overall = list(coverage = mean(m$covered), se_ratio = mean(vapply(rows, `[[`, 0, "se_ratio"))),
    rows = rows
  )
})

mc_se <- sqrt(0.95 * 0.05 / REPS)
coverage <- list(
  generated = format(Sys.Date()),
  reps = REPS,
  policies = N_POLICIES,
  monte_carlo_se = mc_se,
  models = lapply(names(tables), function(n) c(list(model = n), tables[[n]]))
)
write_json(coverage, "dashboard/src/coverage.json", auto_unbox = TRUE, digits = NA)

fmt <- function(x, d = 3) formatC(x, format = "f", digits = d)
pct <- function(x) paste0(fmt(100 * x, 1), "%")
lines <- c(
  "# Interval coverage",
  "",
  "Written by `scripts/coverage_study.R`. The study simulates",
  sprintf("%d portfolios of %s policies from the true model in `scripts/simulate.R`, refits the", REPS,
          format(N_POLICIES, big.mark = ",")),
  "final models on each, and counts how often the 95% Wald intervals contain the true value.",
  sprintf("With %d portfolios, the Monte Carlo standard error of a coverage near 95%% is %s points,", REPS,
          fmt(100 * mc_se, 1)),
  "so a single row between about 92% and 98% is consistent with correct intervals.",
  "",
  "SE ratio is the mean standard error over the standard deviation of the estimates across",
  "portfolios: 1 means the standard errors are the right size, below 1 means they are too small.",
  "Relativities are on the log scale. The premium rows are the expected annual cost of six fixed",
  "profiles, the interval shown in the calculator.",
  "",
  "## Summary",
  "",
  "| Model | Coverage | Mean SE ratio |",
  "| --- | --- | --- |",
  vapply(names(tables), function(n) sprintf("| %s | %s | %s |", n, pct(tables[[n]]$overall$coverage),
                                            fmt(tables[[n]]$overall$se_ratio, 2)), "")
)
for (n in names(tables)) {
  lines <- c(lines, "", paste("##", n), "",
             "| Target | Coverage | SE ratio | Bias (log) |",
             "| --- | --- | --- | --- |",
             vapply(tables[[n]]$rows, function(r) sprintf("| %s | %s | %s | %s |", r$target, pct(r$coverage),
                                                          fmt(r$se_ratio, 2), fmt(r$bias, 4)), ""))
}
writeLines(lines, "reports/coverage.md")
cat(lines, sep = "\n")
cat(sprintf("\n%.1f minutes on %d cores\n", elapsed, CORES))
