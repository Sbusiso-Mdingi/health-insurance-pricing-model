# Health Insurance Pricing Model

A frequency-severity pricing model for health insurance, built in R on a synthetic portfolio
of 100,000 policies. A Poisson GLM predicts how often a policyholder claims, a Gamma GLM
predicts what each claim costs, and the two combine into a pure premium and a loaded premium.
The models are fitted on 80% of the portfolio and checked on the other 20%, and because the
data is synthetic, the fitted effects are also compared with the true ones.

**Live calculator:** https://brave-desert-0f162c50f.3.azurestaticapps.net
(also embedded at https://mdingi.co.za/work/health-insurance-pricing-model)

## Results

From `reports/validation.md`, on the 20,225 holdout policies (18,400 policy years, 5,914 claims):

| Check | Result |
| --- | --- |
| Actual over expected claim cost | 1.010 |
| Actual over expected claim count | 0.989 |
| Gini of the pure premium | 0.546, against 0.547 for the true generating model |
| Poisson dispersion (training) | 0.991, so no overdispersion |
| Gamma dispersion (training) | 0.898, against a true squared CV of 0.896 |
| Relativity intervals containing the true value | 11 of 12 |

The one miss is the smoker effect on claim cost: 1.596 fitted, 1.649 true, with a 95% interval
of 1.554 to 1.638. With twelve 95% intervals, one miss is in line with chance. The frequency
model explains 12.2% of the holdout Poisson deviance, which is normal for claim counts: most of
the difference between two policies' claims in a year is chance, not rating factors.

## Data

`scripts/synthetic_data_generation.R` simulates the portfolio with known parameters:

| Variable | Generation |
| --- | --- |
| Age | Uniform whole years, 18 to 85 |
| Sex | Female 52%, male 48% |
| Region | Southeast 35%, southwest 25%, northeast 20%, northwest 20% |
| Children | Poisson with mean min(age / 30, 2), capped at 5 |
| Smoker | Probability plogis(-3 + 0.04 age) |
| BMI | Lognormal, rising with age, for men and for smokers, clipped to 18 to 45 |
| Exposure | One policy year for 80% of policies, uniform 0.1 to 1 for the rest |
| ClaimCount | Poisson with rate exposure x exp(-2.5 + 0.015 age + 0.03 (BMI - 25) + 0.6 smoker + 0.08 children + 0.2 southeast) |
| Charges | Sum over the policy's claims of independent lognormal costs, meanlog 8 + 0.01 age + 0.02 (BMI - 25) + 0.5 smoker + 0.1 children, sdlog 0.8 |

Sex has no true effect on either component, and region affects frequency only through the
southeast. These null effects are a check that the models do not find what is not there.

## Models

`scripts/model_training.R` fits both models on a random 80% of policies:

- **Frequency:** Poisson GLM with a log link, `ClaimCount ~ ns(Age, 4) + ns(BMI, 4) + Sex +
  Smoker + Children + Region + offset(log(Exposure))`.
- **Severity:** Gamma GLM with a log link on the average cost per claim, weighted by the claim
  count, with the same rating factors. Weighting by claim count makes this equivalent to
  fitting every claim separately.
- **Premium:** pure premium = expected claims per policy year x expected cost per claim, and
  annual premium = pure premium x (1 + loading).
- **Risk classes:** the quartiles of the pure premium over the holdout portfolio (low,
  moderate, high and very high).

The script then validates on the holdout (actual over expected, lift in ten bands of equal
exposure, Lorenz curve and Gini), compares relativities with the true parameters, and writes:

- `models/freq_model.rds`, `models/sev_model.rds` and `models/portfolio_percentiles.rds`
- `reports/validation.md`
- `dashboard/src/model.json`, the coefficients and validation results for the calculator
- `dashboard/test/parity-cases.json`, R's predictions for 300 random profiles

## Calculator

`dashboard/` is a React and TypeScript page with three views: pricing a policy with the
factor-by-factor build-up of the premium, fitted against true rating factors, and the holdout
checks. Both GLMs are additive on the log scale, so the export holds each factor's term, with
age and BMI tabulated at every value the calculator accepts. The parity test checks that the
calculator matches R's `predict()` on all 300 profiles to within 1e-9.

```bash
Rscript scripts/synthetic_data_generation.R
Rscript scripts/model_training.R
cd dashboard && bun install && bun test && bun run build
```

The build is a static site, hosted on Azure Static Web Apps. The original Shiny app in
`shiny-app/` uses the same fitted models: `cd shiny-app && Rscript -e 'shiny::runApp()'`.

## Limitations

- Synthetic data: the premiums are illustrative, not real insurance rates.
- Frequency and severity are independent by construction, and the loading is a flat
  percentage.
- No deductibles, benefit limits, inflation, large-claim treatment or credibility weighting.
- The rating factors are fitted as additive on the log scale, with no interactions.

## Structure

```
data/        synthetic_health_insurance_data.csv
scripts/     synthetic_data_generation.R, model_training.R
models/      fitted models and portfolio percentiles
reports/     pricing_methodology.md, validation.md
dashboard/   React calculator, model export and parity test
shiny-app/   original Shiny app
```

Sbusiso Mdingi
