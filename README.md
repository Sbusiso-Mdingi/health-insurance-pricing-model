# Health Insurance Pricing Model

An end-to-end actuarial pricing framework that uses synthetic health insurance data to model **claim frequency**, **claim severity**, and calculate **individual policy premiums**. This project demonstrates practical techniques in actuarial modelling, statistical learning, and insurance pricing workflows.

---

## 🚀 Project Overview

Pricing health insurance requires understanding how demographic, behavioural, and geographic factors influence claim occurrence and cost.  

This project constructs a **synthetic health insurance dataset** and develops a **frequency–severity pricing model** to estimate expected annual premiums per policyholder. The workflow mirrors real world actuarial practices and includes:

- Synthetic data generation
- Poisson regression for claim frequency
- Lognormal regression for claim severity
- Premium calculation with loadings
- Risk segmentation and portfolio level analysis
- Interactive Shiny app for real-time premium estimation

It serves as both a technical demonstration and a practical exercise in insurance analytics.

---

## 🧠 Pricing Objectives

The project addresses the following objectives:

- **Fair Pricing** – Estimate premiums based on observable risk factors such as age, smoking status, BMI, region, and number of dependents.
- **Risk Differentiation** – Distinguish low, medium, and high risk policyholders.
- **Portfolio Consistency** – Maintain coherent premiums across both frequency and severity components.
- **Transparency** – Use interpretable models for both individual level and aggregate level analysis.
- **End-to-End Workflow** – From synthetic data generation to Shiny based premium calculation.

---

## 📊 Data Generation

The dataset contains **100,000 synthetic policyholders** with the following variables:

| Variable  | Description |
|-----------|------------|
| Age       | Policyholder age (years) |
| Sex       | Biological sex |
| Region    | Geographical region |
| Smoker    | Smoking status (yes/no) |
| Children  | Number of dependents |
| BMI       | Body Mass Index |
| ClaimCount| Number of claims in a year |
| Charges   | Total claim cost for the year |

### Variable Generation Process

- **Age:** Truncated Gompertz distribution (18–85 years)
- **Sex:** Male/female (0.48 / 0.52 probabilities)
- **Region:** Four regions with realistic population weights
- **Children:** Poisson distribution with age-dependent mean, capped at 5
- **Smoker:** Age dependent probability curve
- **BMI:** Lognormal with demographic and smoking effects
- **ClaimCount:** Poisson with demographic and behavioural predictors
- **Charges:** Lognormal with predictors aligned with frequency variables

---

## 🔢 Modelling Pipeline

### Frequency Model
- **Poisson regression** for claim counts
- Predictors: Age, Sex, BMI, Smoker, Children, Region
- Natural cubic splines applied to Age and BMI
- Validated for overdispersion (dispersion statistic ≈ 1.01)
- Alternative Negative Binomial considered but unnecessary

### Severity Model
- **Lognormal regression** for claim costs
- Predictors mirror the frequency model
- Log-transformation applied to stabilize variance
- Residual analysis confirms acceptable model fit

### Pure Premium & Loadings
- Pure premium = Expected frequency × Expected severity
- Final premium = Pure premium × (1 + Loading factor)
- Optional Shiny app allows interactive loading adjustment

### Risk Segmentation
- Quartiles of pure premium used to define:
  - Low Risk
  - Medium Risk
  - High Risk
  - Very High Risk
- Enables portfolio level analysis and underwriting differentiation

---

## 🧪 Results

- Portfolio-level expected loss ratio: ~0.77 (commercially reasonable)
- Premiums increase monotonically with risk factors
- Strong compounding effects observed for age, smoking, BMI, and dependents
- Distribution of premiums confirms effective risk differentiation
- Model outputs are statistically stable and interpretable

---

## 🧰 Tech Stack

- **R** – Core programming and modelling
- **Shiny** – Interactive premium calculator
- **dplyr, splines, MASS, broom, bslib** – Data manipulation and modelling
- **Synthetic dataset** – Fully reproducible without confidential data

---

## 📁 Project Structure

health-insurance-pricing/
├── data/
│   └── synthetic_health_insurance_data.csv
├── models/
│   ├── freq_model.rds
│   ├── sev_model.rds
│   └── sigma_hat.rds
├── shiny-app/
│   └── app.R
├── scripts/
│   ├── synthetic_data_generation.R
│   └── model_training.R
├── reports/
│   └── pricing_methodology.md
├── README.md
└── renv.lock

---

## ⚖️ Limitations

- Simplifying assumptions: independence of frequency and severity, flat loading
- Extreme claims may be underpredicted
- Synthetic dataset assumptions may limit direct applicability to real portfolios
- Designed for educational and demonstration purposes

---

## 🧪 Future Work

- Introduce segment-specific loadings
- Include reinsurance and expense modelling
- Extend to multi-year experience rating
- Explore more advanced tail modelling for catastrophic claims

---

## ⚠️ Disclaimer

This project is intended for **educational and research purposes only**.  
Premiums and risk models are based on **synthetic data** and are **not for commercial use**.

---

## 👨‍💻 Author

**Sbusiso Mdingi**
