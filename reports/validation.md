# Validation results

Written by `scripts/model_training.R`. The models are fitted on a random 80% of the
synthetic portfolio and checked on the remaining 20%. Because the data is synthetic,
the fitted effects can also be compared with the true parameters used to generate it.

## Fit

- Training set: 79,775 policies, 23,637 claims.
- Frequency model Pearson dispersion: 0.991 (1 means no overdispersion).
- Severity model Gamma dispersion: 0.898 (the true lognormal severity has a squared coefficient of variation of 0.896).

## Holdout

- Holdout set: 20,225 policies, 18,400 policy years, 5,914 claims.
- Actual over expected claim count: 0.989.
- Actual over expected claim cost: 1.010.
- Poisson deviance explained by the frequency model: 12.2%.
- Gini of the pure premium: 0.546, against 0.547 for the true generating model.

## Lift by predicted cost band

Ten bands of equal exposure, from lowest to highest predicted cost per policy year.

| Band | Policies | Predicted | Actual | True expected |
| --- | --- | --- | --- | --- |
| 1 | 2,042 | 631 | 619 | 626 |
| 2 | 2,029 | 887 | 847 | 881 |
| 3 | 2,005 | 1,176 | 1,096 | 1,170 |
| 4 | 2,011 | 1,577 | 1,627 | 1,556 |
| 5 | 2,003 | 2,121 | 1,904 | 2,072 |
| 6 | 2,024 | 2,807 | 2,694 | 2,746 |
| 7 | 2,032 | 3,822 | 3,727 | 3,751 |
| 8 | 2,028 | 5,685 | 5,662 | 5,602 |
| 9 | 2,031 | 9,237 | 10,333 | 9,182 |
| 10 | 2,020 | 17,035 | 16,939 | 16,959 |

## Relativities against the true parameters

Multiplicative effect on the base profile, with 95% Wald intervals.

| Factor | Level | Frequency [95% CI] | True | Severity [95% CI] | True |
| --- | --- | --- | --- | --- | --- |
| Sex | male | 0.997 [0.972, 1.023] | 1.000 | 0.990 [0.967, 1.015] | 1.000 |
| Smoker | yes | 1.835 [1.785, 1.887] | 1.822 | 1.596 [1.554, 1.638] | 1.649 |
| Children | each child | 1.091 [1.080, 1.101] | 1.083 | 1.098 [1.088, 1.109] | 1.105 |
| Region | northwest | 0.977 [0.936, 1.019] | 1.000 | 1.008 [0.968, 1.049] | 1.000 |
| Region | southeast | 1.213 [1.170, 1.257] | 1.221 | 1.022 [0.987, 1.057] | 1.000 |
| Region | southwest | 0.989 [0.951, 1.030] | 1.000 | 1.018 [0.980, 1.057] | 1.000 |
