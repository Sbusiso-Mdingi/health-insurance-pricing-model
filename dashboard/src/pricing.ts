/*
 * The rating algorithm, applied to the coefficients exported by
 * scripts/model_training.R. Both GLMs are additive on the log scale, so a
 * prediction is the base profile's log value plus one term per factor.
 */
import model from "./model.json";

export type Sex = "female" | "male";
export type Smoker = "no" | "yes";
export type Region = "northeast" | "northwest" | "southeast" | "southwest";
export type Profile = {
  age: number;
  bmi: number;
  sex: Sex;
  smoker: Smoker;
  region: Region;
  children: number;
};

type Glm = (typeof model)["frequency"];

export const MODEL = model;
export const REGIONS: Region[] = ["northeast", "northwest", "southeast", "southwest"];
export const AGE_RANGE = model.ranges.age as [number, number];
export const BMI_RANGE = model.ranges.bmi as [number, number];
export const BASE: Profile = {
  age: model.base_profile.Age,
  bmi: model.base_profile.BMI,
  sex: model.base_profile.Sex as Sex,
  smoker: model.base_profile.Smoker as Smoker,
  region: model.base_profile.Region as Region,
  children: model.base_profile.Children,
};

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
export const ageIndex = (age: number) => clamp(Math.round(age), AGE_RANGE[0], AGE_RANGE[1]) - AGE_RANGE[0];
export const bmiIndex = (bmi: number) =>
  Math.round((clamp(bmi, BMI_RANGE[0], BMI_RANGE[1]) - BMI_RANGE[0]) * 10);

/** Log-scale contribution of each factor, relative to the base profile. */
function terms(m: Glm, p: Profile) {
  return {
    age: m.age[ageIndex(p.age)],
    bmi: m.bmi[bmiIndex(p.bmi)],
    sex: m.sex[p.sex],
    smoker: m.smoker[p.smoker],
    children: m.children * clamp(Math.round(p.children), 0, 5),
    region: m.region[p.region],
  };
}

export type FactorKey = keyof ReturnType<typeof terms>;
export const FACTORS: { key: FactorKey; label: string }[] = [
  { key: "age", label: "Age" },
  { key: "bmi", label: "BMI" },
  { key: "sex", label: "Sex" },
  { key: "smoker", label: "Smoker" },
  { key: "children", label: "Children" },
  { key: "region", label: "Region" },
];

const sum = (t: Record<string, number>) => Object.values(t).reduce((a, b) => a + b, 0);

export function quote(p: Profile) {
  const f = terms(model.frequency, p);
  const s = terms(model.severity, p);
  const frequency = Math.exp(model.frequency.base + sum(f));
  const severity = Math.exp(model.severity.base + sum(s));
  return {
    frequency,
    severity,
    pure: frequency * severity,
    base: {
      frequency: Math.exp(model.frequency.base),
      severity: Math.exp(model.severity.base),
      pure: Math.exp(model.frequency.base + model.severity.base),
    },
    factors: FACTORS.map(({ key, label }) => ({
      key,
      label,
      frequency: Math.exp(f[key]),
      severity: Math.exp(s[key]),
      combined: Math.exp(f[key] + s[key]),
    })),
  };
}

/** Share of the holdout portfolio (0 to 100) with a lower pure premium. */
export function portfolioPercentile(pure: number) {
  const q = model.portfolio.percentiles;
  if (pure <= q[0]) return 0;
  if (pure >= q[q.length - 1]) return 100;
  let i = 0;
  while (q[i + 1] < pure) i++;
  return i + (pure - q[i]) / (q[i + 1] - q[i]);
}

export const RISK_CLASSES = [
  { label: "Low risk", tone: "low" },
  { label: "Moderate risk", tone: "moderate" },
  { label: "High risk", tone: "high" },
  { label: "Very high risk", tone: "very-high" },
] as const;

export const riskClass = (percentile: number) => RISK_CLASSES[Math.min(3, Math.floor(percentile / 25))];

export const QUARTILES = [25, 50, 75].map((p) => model.portfolio.percentiles[p]);
