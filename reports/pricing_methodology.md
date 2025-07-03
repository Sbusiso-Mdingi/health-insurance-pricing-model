# Health Insurance Pricing Methodology

## 1. Purpose and Scope

This document outlines the actuarial methodology used to construct a health insurance pricing model based on a **frequency–severity framework**.  
The objective of the project is to demonstrate end-to-end pricing logic, from data generation and model estimation to premium calculation and deployment via an interactive Shiny dashboard.

All data used in this project is **fully synthetic** and generated for demonstration purposes only.  
The model outputs should not be interpreted as real world insurance rates.

---

## 2. Pricing Framework Overview

The premium calculation follows a standard actuarial structure:

**Pure Premium = Expected Claim Frequency × Expected Claim Severity**

A loading factor is subsequently applied to account for non-claim costs and margin:

**Final Premium = Pure Premium × (1 + Loading)**

Where:
- Frequency is modeled using a Poisson generalized linear model
- Severity is modeled using a Lognormal regression model
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

Claim counts are generated from a Poisson distribution, while claim severities follow a Lognormal distribution.

---

## 4. Claim Frequency Model

### 4.1 Model Specification

Claim frequency is modeled using a Poisson GLM with a log link function:

ClaimCount ~ ns(Age) + ns(BMI) + Sex + Smoker + Children + Region

Where:
- Natural splines are used for Age and BMI to capture non-linear effects
- Categorical variables are included as rating factors

### 4.2 Rationale

The Poisson distribution is appropriate for modeling discrete claim counts over a fixed exposure period.  
Spline terms allow for flexibility without imposing rigid linear assumptions.

---

## 5. Claim Severity Model

### 5.1 Model Specification

Claim severity is modeled using a Lognormal regression applied to policyholders with at least one claim:

log(Charges) ~ ns(Age) + ns(BMI) + Sex + Smoker + Children + Region

The residual standard deviation of the log-scale model (σ) is estimated and stored separately.

### 5.2 Expected Severity Calculation

The expected claim severity is recovered using the standard Lognormal correction:


This ensures unbiased severity estimates on the original monetary scale.

---

## 6. Premium Calculation

For a given policyholder profile:

1. Predict expected claim frequency from the Poisson model
2. Predict expected claim severity from the Lognormal model
3. Compute the pure premium as the product of frequency and severity
4. Apply a configurable loading factor

The loading factor is adjustable within the Shiny application to reflect different expense and margin assumptions.

---

## 7. Risk Classification

Policyholders are categorized into **Low**, **Medium**, or **High** risk classes based on their estimated pure premium relative to the portfolio distribution.

This classification is intended for:
- Communication and visualization
- Relative risk assessment
- Dashboard interpretability

It is not intended as a regulatory or underwriting classification.

---

## 8. Model Limitations

This implementation is subject to several limitations:

- No exposure adjustment or partial-year modeling
- No policy deductibles, limits, or benefit design
- No dependence between frequency and severity
- No inflation or trend assumptions
- No credibility or experience rating components

These limitations are intentional to maintain clarity and focus on core pricing mechanics.

---

## 9. Reproducibility

The project is fully reproducible using the provided `renv.lock` file.  
All models can be retrained from scratch by running the scripts in the `scripts/` directory in sequence.

---

## 10. Intended Use

This project is intended for:
- Educational purposes
- Portfolio demonstration
- Technical skill validation

It does not represent production pricing software and should not be used for real world insurance decision making.

