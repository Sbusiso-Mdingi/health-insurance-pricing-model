# Health Insurance Pricing Methodology

## 1. Purpose and Scope

This document outlines the actuarial methodology used to construct a health insurance pricing model based on a **frequency-severity framework**.  
The objective of the project is to demonstrate end-to-end pricing logic, from data generation and model estimation to validation, premium calculation and an interactive calculator.

All data used in this project is **fully synthetic** and generated for demonstration purposes only.  
The model outputs should not be interpreted as real world insurance rates.

---

## 2. Pricing Framework Overview

The premium calculation follows a standard actuarial structure:

**Pure Premium = Expected Claim Frequency × Expected Claim Severity**

A loading factor is subsequently applied to account for non-claim costs and margin:

**Final Premium = Pure Premium × (1 + Loading)**

Where:
- Frequency is the expected number of claims per policy year, modeled with a Poisson GLM
- Severity is the expected cost per claim, modeled with a Gamma GLM
- Rating variables are shared across both components

---

## 3. Data Generation Assumptions

A synthetic portfolio of policyholders was generated with realistic demographic and behavioral characteristics, including:

- Age
- Sex
- Body Mass Index (BMI)
- Smoking status
- Geographic region
- Number of dependent children

The data generation process embeds plausible actuarial relationships, such as:
- Increasing claim frequency with age, BMI, and smoking
- Higher severity for smokers and older policyholders
- Regional variation in utilization

Each policy has an exposure in policy years: 80% are in force for the whole year and the rest for between 0.1 and 1 year. Claim counts are Poisson with a mean proportional to exposure, and every claim has its own independent lognormal cost; a policy's charges are the sum over its claims. The exact parameters are listed in the README and in `scripts/synthetic_data_generation.R`, so the fitted effects can be compared with the true ones.

---

## 4. Claim Frequency Model

### 4.1 Model Specification

Claim frequency is modeled using a Poisson GLM with a log link function and log exposure as an offset:

ClaimCount ~ ns(Age, 4) + ns(BMI, 4) + Sex + Smoker + Children + Region + offset(log(Exposure))

Where:
- Natural splines are used for Age and BMI to capture non-linear effects
- Categorical variables are included as rating factors

### 4.2 Rationale

The Poisson distribution is appropriate for modeling discrete claim counts, and the offset makes the fitted rate a rate per policy year, so partial-year policies are not mistaken for low risks.  
Spline terms allow for flexibility without imposing rigid linear assumptions. The Pearson dispersion of the fitted model is 0.991, so a negative binomial model is not needed.

---

## 5. Claim Severity Model

### 5.1 Model Specification

Claim severity is modeled using a Gamma GLM with a log link, fitted to the average cost per claim on policies with at least one claim, weighted by the number of claims:

AvgCost ~ ns(Age, 4) + ns(BMI, 4) + Sex + Smoker + Children + Region,  weights = ClaimCount

### 5.2 Rationale

The variance of an average of k claims is the per-claim variance divided by k, so weighting by claim count makes the fit equivalent to fitting every claim separately. A Gamma GLM with a log link models the mean cost directly, so no retransformation is needed: the expected cost per claim is exp(x'b). The true severities are lognormal, but the log-link mean is still correctly specified, and the fitted Gamma dispersion (0.898) is close to the lognormal's squared coefficient of variation, exp(0.8^2) - 1 = 0.896.

An earlier version of this project fitted a lognormal regression to each policy's total annual charges and multiplied its mean by the expected claim count. Because total charges already scale with the number of claims, that counted claim frequency twice. Fitting severity per claim removes the double count.

---

## 6. Premium Calculation

For a given policyholder profile:

1. Predict the expected claims per policy year from the Poisson model
2. Predict the expected cost per claim from the Gamma model
3. Compute the pure premium as the product of frequency and severity
4. Apply a configurable loading factor: Final Premium = Pure Premium x (1 + Loading)

Because both models are additive on the log scale, the pure premium is the base profile's premium multiplied by one relativity per rating factor. The calculator shows this build-up, and the loading is adjustable to reflect different expense and margin assumptions.

---

## 7. Validation

The models are fitted on a random 80% of policies and validated on the other 20%. The checks, with results in `reports/validation.md`, are:

- Actual over expected claim count and claim cost on the holdout (0.989 and 1.010)
- Lift across ten bands of equal exposure, ordered by predicted cost per policy year
- The exposure-weighted Lorenz curve and Gini of the pure premium (0.546), against the Gini of the true generating model on the same policies (0.547)
- Fitted relativities and 95% Wald intervals against the true parameters (11 of 12 intervals contain the true value)

---

## 8. Risk Classification

Policyholders are categorized into **Low**, **Moderate**, **High** or **Very high** risk classes by the quartile of the holdout portfolio's pure premium distribution that their pure premium falls in.

This classification is intended for:
- Communication and visualization
- Relative risk assessment
- Dashboard interpretability

It is not intended as a regulatory or underwriting classification.

---

## 9. Model Limitations

This implementation is subject to several limitations:

- No policy deductibles, limits, or benefit design
- No dependence between frequency and severity
- No inflation or trend assumptions
- No credibility or experience rating components
- No interactions between rating factors

These limitations are intentional to maintain clarity and focus on core pricing mechanics.

---

## 10. Reproducibility

All data and models can be regenerated from scratch by running `scripts/synthetic_data_generation.R` and then `scripts/model_training.R` from the project root. The `renv.lock` file records the package versions of the original Shiny app.

---

## 11. Intended Use

This project is intended for:
- Educational purposes
- Portfolio demonstration
- Technical skill validation

It does not represent production pricing software and should not be used for real world insurance decision making.

