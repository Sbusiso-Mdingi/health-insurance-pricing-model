# Validation results

Written by `scripts/model_training.R`. The models are fitted on a random 80% of the
synthetic portfolio and checked on the remaining 20%. Because the data is synthetic,
the fitted effects can also be compared with the true parameters in `scripts/simulate.R`.

## Model comparison

Candidate rating structures. Every candidate also includes Smoker, Children, Province
and Plan.

| Name | Age, BMI and sex terms |
| --- | --- |
| F1, S1 | linear Age and BMI, Sex |
| F2, S2 | ns(Age, 4), ns(BMI, 4), Sex |
| F3 | ns(Age, 10) x Sex interaction, ns(BMI, 4) |
| S3 | ns(Age, 4) x Sex interaction, ns(BMI, 4) |

### Frequency

Training AIC, and holdout Poisson deviance explained and Gini of claim counts.

| Model | Family | Parameters | AIC | Deviance explained | Gini |
| --- | --- | --- | --- | --- | --- |
| F1 | poisson | 16 | 266,044 | 49.6% | 0.481 |
| F1 | negbin | 17 | 250,632 | 49.6% | 0.481 |
| F2 | poisson | 22 | 264,545 | 50.1% | 0.483 |
| F2 | negbin | 23 | 249,931 | 50.1% | 0.483 |
| F3 | poisson | 38 | 263,785 | 50.5% | 0.485 |
| F3 | negbin | 39 | 249,524 | 50.5% | 0.485 |

The Poisson F3 model has a Pearson dispersion of 1.604, so the claim counts are overdispersed and Poisson standard errors are too small. The negative binomial estimates theta = 3.323 (standard error 0.049), against a true value of 3.333.

### Severity

Gamma GLMs. Training AIC and dispersion, and holdout Gamma deviance explained and Gini
of claim cost by predicted cost per claim.

| Model | Parameters | AIC | Dispersion | Deviance explained | Gini |
| --- | --- | --- | --- | --- | --- |
| S1 | 16 | 3,428,614 | 3.046 | 26.7% | 0.247 |
| S2 | 22 | 3,428,542 | 3.052 | 26.7% | 0.248 |
| S3 | 26 | 3,428,515 | 3.045 | 26.8% | 0.248 |

### Selection

Nested tests on the training set, adding terms only at the 5% level: likelihood ratio
tests for the negative binomial models, and F tests with the estimated dispersion for the
Gamma models (the Gamma AIC assumes Gamma distributed claims, which these are not).

| Test | Statistic | df | p-value |
| --- | --- | --- | --- |
| F1 to F2 (LR) | 713.3 | 6 | < 0.001 |
| F2 to F3 (LR) | 438.3 | 16 | < 0.001 |
| S1 to S2 (F) | 2.19 | 6 | 0.041 |
| S2 to S3 (F) | 1.36 | 4 | 0.243 |

The degrees of freedom of F3's age spline are chosen by AIC (negative binomial, training set): 6 df 249,532.0, 8 df 249,531.7, 10 df 249,524.4, 12 df 249,528.5. A first version with 6 degrees of freedom smoothed away the maternity peak in women's claim frequency, and the coverage study showed it: premium intervals for women aged 31 and 40 contained the true value only 77% to 80% of the time.

Final models: F3 negative binomial for frequency and S2 Gamma for severity.

### Pure premium

Holdout cost per policy year. Deviance explained uses the Tweedie deviance with power 1.6.

| Model | Deviance explained | Gini | Actual over expected |
| --- | --- | --- | --- |
| F1 x S1, linear | 15.4% | 0.363 | 0.991 |
| F2 x S2, splines | 15.8% | 0.367 | 0.987 |
| F3 x S2, final | 15.9% | 0.369 | 0.988 |
| F3 x S3 | 15.9% | 0.369 | 0.988 |
| Tweedie GLM, F3 terms | 15.9% | 0.369 | 0.987 |
| True model | 15.9% | 0.369 | 0.984 |

## Fit

- Training set: 79,775 policies, 72,511 policy years, 159,865 claims.
- Severity Gamma dispersion: 3.052, against a true squared coefficient of variation per claim of 3.373.

## Holdout

- Holdout set: 20,225 policies, 18,451 policy years, 40,140 claims.
- Actual over expected claim count: 0.999.
- Actual over expected claim cost: 0.988.
- Deviance explained: frequency 50.5%, severity 26.7%, cost per policy year 15.9%.
- Gini of the pure premium: 0.369, against 0.369 for the true generating model.

### Actual over expected by plan and province

| Group | Policy years | Claims | Cost |
| --- | --- | --- | --- |
| Hospital | 6,471 | 1.019 | 0.963 |
| Saver | 8,799 | 0.990 | 0.979 |
| Comprehensive | 3,181 | 1.004 | 1.018 |
| Gauteng | 6,917 | 0.999 | 0.995 |
| Western Cape | 3,166 | 1.014 | 0.997 |
| KwaZulu-Natal | 2,859 | 0.995 | 0.989 |
| Eastern Cape | 1,321 | 1.001 | 0.986 |
| Free State | 921 | 0.996 | 0.973 |
| Limpopo | 866 | 1.039 | 0.993 |
| Mpumalanga | 1,109 | 0.961 | 0.929 |
| North West | 950 | 0.956 | 0.955 |
| Northern Cape | 341 | 1.001 | 1.010 |

## Lift by predicted cost band

Ten bands of equal exposure, from lowest to highest predicted cost per policy year.

| Band | Policies | Predicted | Actual | True expected |
| --- | --- | --- | --- | --- |
| 1 | 2,023 | 12,145 | 10,676 | 12,288 |
| 2 | 2,037 | 18,423 | 18,457 | 18,640 |
| 3 | 2,013 | 23,540 | 23,518 | 23,796 |
| 4 | 2,023 | 28,557 | 25,655 | 28,820 |
| 5 | 2,026 | 33,806 | 34,757 | 34,054 |
| 6 | 2,028 | 39,907 | 38,978 | 40,112 |
| 7 | 2,021 | 47,585 | 48,120 | 47,635 |
| 8 | 2,011 | 57,581 | 57,746 | 57,513 |
| 9 | 2,025 | 74,217 | 73,566 | 74,087 |
| 10 | 2,018 | 125,329 | 123,894 | 125,697 |

## Relativities against the true parameters

Multiplicative effect on the base profile, with 95% Wald intervals. Sex is compared for
severity only, because its frequency effect depends on age.
24 of 25 intervals contain the true value.

| Factor | Level | Frequency [95% CI] | True | Severity [95% CI] | True |
| --- | --- | --- | --- | --- | --- |
| Smoker | yes | 1.304 [1.282, 1.327] | 1.297 | 1.268 [1.241, 1.295] | 1.246 |
| Children | each child | 1.252 [1.243, 1.262] | 1.246 | 0.924 [0.916, 0.933] | 0.930 |
| Sex | male |  |  | 1.052 [1.033, 1.071] | 1.050 |
| Plan | Saver | 4.026 [3.943, 4.111] | 4.000 | 0.453 [0.438, 0.468] | 0.450 |
| Plan | Comprehensive | 10.057 [9.834, 10.284] | 10.000 | 0.250 [0.242, 0.259] | 0.250 |
| Province | Western Cape | 0.969 [0.950, 0.988] | 0.970 | 1.024 [0.998, 1.049] | 1.020 |
| Province | KwaZulu-Natal | 0.951 [0.932, 0.971] | 0.951 | 0.963 [0.939, 0.989] | 0.961 |
| Province | Eastern Cape | 0.909 [0.883, 0.935] | 0.905 | 0.918 [0.885, 0.951] | 0.923 |
| Province | Free State | 0.904 [0.874, 0.934] | 0.923 | 0.927 [0.889, 0.967] | 0.932 |
| Province | Limpopo | 0.864 [0.835, 0.894] | 0.861 | 0.895 [0.857, 0.935] | 0.905 |
| Province | Mpumalanga | 0.928 [0.900, 0.957] | 0.905 | 0.930 [0.896, 0.966] | 0.942 |
| Province | North West | 0.935 [0.905, 0.966] | 0.905 | 0.921 [0.885, 0.959] | 0.923 |
| Province | Northern Cape | 0.874 [0.831, 0.920] | 0.887 | 0.899 [0.842, 0.959] | 0.914 |

## Interval coverage

From `scripts/coverage_study.R`: 200 portfolios of 80,000 policies simulated from the true model and refitted, counting how often the 95% intervals contain the true value (Monte Carlo standard error 1.5 points). SE ratio is the mean standard error over the spread of the estimates; 1 means the standard errors are the right size. Details in `reports/coverage.md`.

| Intervals | Coverage | Mean SE ratio |
| --- | --- | --- |
| Frequency, negative binomial | 95.0% | 0.99 |
| Frequency, Poisson | 83.3% | 0.70 |
| Severity, Gamma | 94.7% | 1.00 |
| Premium, negative binomial x Gamma | 92.5% | 0.99 |
| Premium, Poisson x Gamma | 87.5% | 0.84 |

Premium intervals (negative binomial x Gamma) for six fixed profiles:

| Profile | Coverage | Bias (log) |
| --- | --- | --- |
| Base: woman, 40, Gauteng, Hospital | 88.0% | 0.0193 |
| Man, 30, smoker, Western Cape, Saver | 94.5% | -0.0046 |
| Woman, 31, 2 children, KwaZulu-Natal, Saver | 91.5% | -0.0106 |
| Woman, 62, BMI 32, Gauteng, Comprehensive | 94.0% | -0.0023 |
| Man, 50, 1 child, Limpopo, Comprehensive | 94.0% | -0.0062 |
| Man, 78, smoker, BMI 30, Northern Cape, Hospital | 93.0% | -0.0008 |

