# Interval coverage

Written by `scripts/coverage_study.R`. The study simulates
200 portfolios of 80,000 policies from the true model in `scripts/simulate.R`, refits the
final models on each, and counts how often the 95% Wald intervals contain the true value.
With 200 portfolios, the Monte Carlo standard error of a coverage near 95% is 1.5 points,
so a single row between about 92% and 98% is consistent with correct intervals.

SE ratio is the mean standard error over the standard deviation of the estimates across
portfolios: 1 means the standard errors are the right size, below 1 means they are too small.
Relativities are on the log scale. The premium rows are the expected annual cost of six fixed
profiles, the interval shown in the calculator.

## Summary

| Model | Coverage | Mean SE ratio |
| --- | --- | --- |
| Frequency, negative binomial | 95.0% | 0.99 |
| Frequency, Poisson | 83.3% | 0.70 |
| Severity, Gamma | 94.7% | 1.00 |
| Premium, negative binomial x Gamma | 92.5% | 0.99 |
| Premium, Poisson x Gamma | 87.5% | 0.84 |

## Frequency, negative binomial

| Target | Coverage | SE ratio | Bias (log) |
| --- | --- | --- | --- |
| Smoker | 96.0% | 1.01 | 0.0010 |
| Each child | 95.5% | 0.97 | 0.0002 |
| Saver plan | 93.0% | 0.95 | 0.0007 |
| Comprehensive plan | 95.5% | 1.03 | 0.0011 |
| Western Cape | 90.5% | 0.89 | -0.0006 |
| KwaZulu-Natal | 96.0% | 1.00 | 0.0015 |
| Eastern Cape | 95.0% | 0.97 | 0.0001 |
| Free State | 95.0% | 0.97 | -0.0018 |
| Limpopo | 97.5% | 1.09 | 0.0007 |
| Mpumalanga | 95.5% | 1.08 | -0.0002 |
| North West | 96.0% | 1.03 | 0.0004 |
| Northern Cape | 94.5% | 0.95 | -0.0003 |

## Frequency, Poisson

| Target | Coverage | SE ratio | Bias (log) |
| --- | --- | --- | --- |
| Smoker | 78.0% | 0.63 | 0.0011 |
| Each child | 82.5% | 0.65 | 0.0003 |
| Saver plan | 91.5% | 0.84 | 0.0007 |
| Comprehensive plan | 90.0% | 0.85 | 0.0012 |
| Western Cape | 77.5% | 0.61 | -0.0004 |
| KwaZulu-Natal | 84.0% | 0.67 | 0.0014 |
| Eastern Cape | 82.0% | 0.65 | 0.0008 |
| Free State | 78.5% | 0.64 | -0.0017 |
| Limpopo | 86.0% | 0.74 | 0.0006 |
| Mpumalanga | 85.5% | 0.75 | -0.0004 |
| North West | 84.0% | 0.68 | -0.0002 |
| Northern Cape | 80.5% | 0.66 | -0.0002 |

## Severity, Gamma

| Target | Coverage | SE ratio | Bias (log) |
| --- | --- | --- | --- |
| Smoker | 94.0% | 1.04 | -0.0004 |
| Each child | 94.5% | 0.96 | 0.0001 |
| Male | 94.0% | 0.98 | 0.0002 |
| Saver plan | 93.5% | 0.98 | -0.0003 |
| Comprehensive plan | 95.0% | 0.99 | -0.0014 |
| Western Cape | 95.0% | 0.99 | 0.0003 |
| KwaZulu-Natal | 96.0% | 0.97 | -0.0001 |
| Eastern Cape | 95.5% | 1.07 | 0.0003 |
| Free State | 94.0% | 0.92 | 0.0009 |
| Limpopo | 95.5% | 1.04 | -0.0031 |
| Mpumalanga | 94.0% | 0.99 | 0.0024 |
| North West | 95.0% | 0.98 | 0.0017 |
| Northern Cape | 95.0% | 1.03 | 0.0028 |

## Premium, negative binomial x Gamma

| Target | Coverage | SE ratio | Bias (log) |
| --- | --- | --- | --- |
| Base: woman, 40, Gauteng, Hospital | 88.0% | 0.95 | 0.0193 |
| Man, 30, smoker, Western Cape, Saver | 94.5% | 1.04 | -0.0046 |
| Woman, 31, 2 children, KwaZulu-Natal, Saver | 91.5% | 0.94 | -0.0106 |
| Woman, 62, BMI 32, Gauteng, Comprehensive | 94.0% | 0.97 | -0.0023 |
| Man, 50, 1 child, Limpopo, Comprehensive | 94.0% | 1.06 | -0.0062 |
| Man, 78, smoker, BMI 30, Northern Cape, Hospital | 93.0% | 0.99 | -0.0008 |

## Premium, Poisson x Gamma

| Target | Coverage | SE ratio | Bias (log) |
| --- | --- | --- | --- |
| Base: woman, 40, Gauteng, Hospital | 84.0% | 0.85 | 0.0190 |
| Man, 30, smoker, Western Cape, Saver | 90.5% | 0.90 | -0.0046 |
| Woman, 31, 2 children, KwaZulu-Natal, Saver | 87.0% | 0.82 | -0.0115 |
| Woman, 62, BMI 32, Gauteng, Comprehensive | 87.0% | 0.76 | -0.0021 |
| Man, 50, 1 child, Limpopo, Comprehensive | 90.0% | 0.89 | -0.0060 |
| Man, 78, smoker, BMI 30, Northern Cape, Hospital | 86.5% | 0.82 | 0.0002 |
