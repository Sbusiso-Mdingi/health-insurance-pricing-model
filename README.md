# Health Insurance Pricing Model

A frequency-severity pricing model for health insurance, built in R on a synthetic South
African portfolio of 100,000 members across the nine provinces and three benefit tiers. A
negative binomial GLM predicts how often a member claims, a Gamma GLM predicts what each claim
costs, and the two combine into a monthly risk premium with a 95% interval. A tariff then
smooths the age curve so the premium never falls with age, and shows the cross-subsidy that
creates. Candidate models
are compared on a holdout, and because the data is synthetic, the fitted effects and the
intervals are also checked against the true ones.

**Live calculator:** https://brave-desert-0f162c50f.3.azurestaticapps.net
(also embedded at https://mdingi.co.za/work/health-insurance-pricing-model)

## Results

From `reports/validation.md`, on the 20,225 holdout policies (18,451 policy years, 40,140 claims):

| Check | Result |
| --- | --- |
| Actual over expected claim cost | 0.988 (the true model scores 0.984 on the same policies) |
| Actual over expected claim count | 0.999 |
| Gini of the pure premium | 0.369, against 0.369 for the true generating model |
| Overdispersion | Poisson dispersion 1.604; negative binomial theta 3.32, against a true 3.33 |
| Relativity intervals containing the true value | 24 of 25 |

From `reports/coverage.md`, refitting on 200 simulated portfolios:

| 95% intervals | Coverage | Mean SE ratio |
| --- | --- | --- |
| Frequency, negative binomial | 95.0% | 0.99 |
| Frequency, Poisson | 83.3% | 0.70 |
| Severity, Gamma | 94.7% | 1.00 |
| Premium, negative binomial x Gamma | 92.5% | 0.99 |

The Poisson model gets the mean right but its standard errors are about 30% too small, which
is why the frequency model is negative binomial. The premium intervals are slightly narrow for
women aged 31 to 40 (88% coverage at age 40): the intervals cover estimation error only, and
the age spline still smooths part of the maternity peak in women's claim frequency.

The holdout cost is 1.2% below expected for the true model as well as the fitted one, so the
shortfall is large-claim noise, not model bias: 3% of claims come from a Pareto tail.

## Data

`scripts/simulate.R` holds every true parameter and the simulation;
`scripts/synthetic_data_generation.R` runs it once (seed 123) and writes
`data/synthetic_health_insurance_data.csv`. The parameters are illustrative assumptions chosen to
look plausible for a health insurance portfolio, not estimates from real data. The provinces
give the portfolio a South African geography; the product is generic health cover.

| Variable | Generation |
| --- | --- |
| Age | Principal members aged 18 to 85, 18 + 67 x Beta(2, 2.8), so working-age heavy |
| Sex | Female 52%, male 48% |
| Province | Gauteng 38%, Western Cape 17%, KwaZulu-Natal 15%, Eastern Cape 7%, Mpumalanga 6%, Free State, Limpopo and North West 5% each, Northern Cape 2% |
| Children | Poisson, peaking for members around 40, capped at 5 |
| Smoker | More common in men and falling with age (about 12% of women and 31% of men) |
| BMI | Lognormal around 26, higher for women, rising with age to 60, clipped to 16 to 50 |
| Plan | Essential (in-hospital treatment), Standard (adds out-of-hospital specialists, scans and tests) or Comprehensive (adds GP visits, prescribed medicines, dental and optical), chosen by a multinomial logit: older members buy richer cover, families lean to Standard |
| Exposure | One policy year for 80% of policies, uniform 0.1 to 1 for the rest |
| ClaimCount | Negative binomial: Poisson given a gamma frailty with variance 0.3 |
| Charges | Sum over the policy's claims of independent costs: lognormal (sdlog 1.1) with probability 0.97, Pareto (alpha 2.3) large claims otherwise |

On the log scale, claim frequency rises 0.025 a year with age and faster after 55, has a
maternity peak for women around 31, rises with BMI above 25 and below 20, and is higher for
smokers (+0.26) and per child (+0.22). Out-of-hospital cover multiplies the number of claims by 4
(Standard) and 10 (Comprehensive) and the cost per claim by 0.45 and 0.25. Provinces outside
Gauteng have lower frequency and cost, in line with lower private hospital use and tariffs.

## Models

`scripts/models.R` defines the candidates and `scripts/model_training.R` compares them on a
random 80% of policies:

| Name | Age, BMI and sex terms |
| --- | --- |
| F1, S1 | linear Age and BMI, Sex |
| F2, S2 | ns(Age, 4), ns(BMI, 4), Sex |
| F3 | ns(Age, 10) x Sex interaction, ns(BMI, 4) |
| S3 | ns(Age, 4) x Sex interaction, ns(BMI, 4) |

Every candidate also includes Smoker, Children, Province and Plan. Frequency candidates are
fitted as Poisson and negative binomial GLMs with an exposure offset; severity candidates as
Gamma GLMs on the average cost per claim, weighted by claim count (equivalent to fitting every
claim). Terms are added by nested tests at the 5% level, likelihood ratio tests for frequency
and F tests with the estimated dispersion for severity, which selects F3 and S2. The severity
age by sex interaction is rejected (p = 0.24), correctly, since the true severity has none.

| Pure premium model, holdout | Tweedie deviance explained | Gini | Actual over expected |
| --- | --- | --- | --- |
| F1 x S1, linear | 15.4% | 0.363 | 0.991 |
| F2 x S2, splines | 15.8% | 0.367 | 0.987 |
| F3 x S2, final | 15.9% | 0.369 | 0.988 |
| F3 x S3 | 15.9% | 0.369 | 0.988 |
| Single Tweedie GLM (power 1.6), F3 terms | 15.9% | 0.369 | 0.987 |
| True model | 15.9% | 0.369 | 0.984 |

The single Tweedie GLM ranks risks as well as the frequency-severity pair, but the pair shows
separately how plans and factors change claim counts and claim sizes, which the calculator uses.

**Premium:** expected claims cost = expected claims per year x expected cost per claim;
annual premium = expected claims cost x (1 + loading); monthly premium = annual / 12. The
calculator's default loading of 15% is an assumption. The 95% interval uses the delta method
on the log scale with each model's coefficient covariance matrix; the two models' estimates are
independent, so their variances add.

**Tariff:** the fitted age factor for women rises to the maternity peak at about 31, dips and
rises again, and a rate table that falls with age would be hard to justify to members. The
tariff replaces each sex's fitted age and sex factor with the closest curve that never falls
with age: a weighted isotonic regression (pool adjacent violators), weighted by the training
portfolio's expected claims at each age. Pooling preserves the weighted total, so the tariff
collects the same premium as the risk premium within each sex, and the difference is a
cross-subsidy between ages. Women aged 31 to 41 pay one pooled factor: at 33 the tariff is 8.3%
below the risk premium, at 38 it is 6.4% above. By band, women aged 30 to 34 pay 5.5% less than
their expected claims, and women aged 35 to 39 and 40 to 44 pay 3.3% and 1.2% more. Men's fitted
factor already rises with age, so their tariff equals their risk premium.

**Risk classes:** the quartiles of the expected claims cost among holdout members on the same
plan, since across plans the cost mostly reflects the benefits bought.

`scripts/coverage_study.R` simulates 200 portfolios of 80,000 policies from the true model,
refits the final models (and the Poisson version) on each, and records how often the intervals
for the relativities and for six fixed profiles' expected cost contain the true value. A first
run with 6 degrees of freedom for the age spline covered women aged 31 and 40 only 77% to 80% of
the time; F3's degrees of freedom are now chosen by AIC, which picks 10.

Outputs:

- `models/freq_model.rds`, `models/sev_model.rds` (with their covariance matrices),
  `models/tariff.rds` and `models/portfolio_percentiles.rds`
- `reports/validation.md` and `reports/coverage.md`, with every estimate in
  `reports/coverage_estimates.csv`
- `dashboard/src/model.json` and `dashboard/src/coverage.json` for the calculator
- `dashboard/test/parity-cases.json`, R's predictions and standard errors for 300 random profiles

## Calculator

`dashboard/` is a React and TypeScript page with three views: pricing a member with the
factor-by-factor build-up, the tariff smoothing and the interval; fitted against true age and
BMI curves and relativities, with the tariff and its cross-subsidy; and the holdout checks, model comparison and coverage. It rebuilds each model's
design row from the coefficient names and the exported spline bases, so the parity test can
check that it matches R's predictions, standard errors and tariff premiums on all 300 profiles
to within 1e-9.

```bash
Rscript scripts/synthetic_data_generation.R
Rscript scripts/coverage_study.R     # about 7 minutes on 8 cores
Rscript scripts/model_training.R
cd dashboard && bun install && bun test && bun run build
```

`.github/workflows/check.yml` reruns the R scripts (with a 4-portfolio coverage study), the
parity test and the build on every push. Package versions are in `renv.lock`.

The build is a static site, hosted on Azure Static Web Apps. The original Shiny app in
`shiny-app/` uses the same fitted models: `cd shiny-app && Rscript -e 'shiny::runApp()'`.

## Limitations

- Synthetic data with illustrative parameters: the premiums are not real rates, and the
  product is generic, not designed against any particular regulatory framework.
- Principal members only; dependants enter through the number of children, and there are no
  adult dependants, waiting periods, exclusions or pre-existing condition rules.
- The tariff only smooths the age curve; it does not round to age bands or cap year-on-year
  increases.
- Frequency and severity are independent by construction, and the loading is a flat
  percentage.
- No excesses, benefit limits, co-payments, inflation or credibility weighting; the tiers
  differ only in scope of cover.

## Structure

```
data/        synthetic_health_insurance_data.csv
scripts/     simulate.R, synthetic_data_generation.R, models.R, model_training.R, coverage_study.R
models/      fitted models and portfolio percentiles
reports/     pricing_methodology.md, validation.md, coverage.md
dashboard/   React calculator, model export and parity test
shiny-app/   original Shiny app
```

Sbusiso Mdingi
