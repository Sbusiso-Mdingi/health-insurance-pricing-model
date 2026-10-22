/*
 * The rating algorithm, applied to the coefficients exported by
 * scripts/model_training.R. Each GLM's design row is rebuilt from its
 * coefficient names: the intercept, factor indicators, Children, and
 * spline columns looked up in the exported basis tables, with ":" marking
 * an interaction. The prediction is exp(x'b), and its standard error on
 * the log scale is sqrt(x'Vx) from the exported covariance matrix.
 */
import model from "./model.json";

export type Sex = "female" | "male";
export type Smoker = "no" | "yes";
export type Profile = {
  age: number;
  bmi: number;
  sex: Sex;
  smoker: Smoker;
  province: string;
  plan: string;
  children: number;
};

type Glm = {
  terms: string[];
  coef: number[];
  vcov: number[][];
  age_basis: Record<string, number[]>;
  bmi_basis: Record<string, number[]>;
};

export const MODEL = model;
export const PROVINCES: string[] = model.provinces;
export const PLANS: string[] = model.plans;
export const AGE_RANGE = model.ranges.age as [number, number];
export const BMI_RANGE = model.ranges.bmi as [number, number];
export const BASE: Profile = {
  age: model.base_profile.Age,
  bmi: model.base_profile.BMI,
  sex: model.base_profile.Sex as Sex,
  smoker: model.base_profile.Smoker as Smoker,
  province: model.base_profile.Province,
  plan: model.base_profile.Plan,
  children: model.base_profile.Children,
};
const FREQUENCY = model.frequency as unknown as Glm;
const SEVERITY = model.severity as unknown as Glm;
const Z95 = 1.959963984540054;
const TARIFF = model.tariff as unknown as Record<Sex, { risk: number[]; tariff: number[] }>;

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
export const ageIndex = (age: number) => clamp(Math.round(age), AGE_RANGE[0], AGE_RANGE[1]) - AGE_RANGE[0];
export const bmiIndex = (bmi: number) =>
  Math.round((clamp(bmi, BMI_RANGE[0], BMI_RANGE[1]) - BMI_RANGE[0]) * 10);

/* Rating variables, in display order. */
type Variable = "Age" | "Sex" | "BMI" | "Smoker" | "Children" | "Province" | "Plan";
const VARIABLES: Variable[] = ["Age", "Sex", "BMI", "Smoker", "Children", "Province", "Plan"];
const FACTOR_VALUE = {
  Sex: (p: Profile) => p.sex,
  Smoker: (p: Profile) => p.smoker,
  Province: (p: Profile) => p.province,
  Plan: (p: Profile) => p.plan,
} as const;

/** The variable a single (non-interaction) column part depends on. */
function variableOf(part: string): Variable | null {
  if (part === "(Intercept)") return null;
  if (part === "Age" || part.startsWith("ns(Age,")) return "Age";
  if (part === "BMI" || part.startsWith("ns(BMI,")) return "BMI";
  if (part === "Children") return "Children";
  for (const v of Object.keys(FACTOR_VALUE) as (keyof typeof FACTOR_VALUE)[]) if (part.startsWith(v)) return v;
  throw new Error(`Unknown model term: ${part}`);
}

function partValue(m: Glm, part: string, p: Profile): number {
  const v = variableOf(part);
  if (v === null) return 1;
  if (part.startsWith("ns(Age,")) return m.age_basis[part][ageIndex(p.age)];
  if (part.startsWith("ns(BMI,")) return m.bmi_basis[part][bmiIndex(p.bmi)];
  if (v === "Age") return p.age;
  if (v === "BMI") return p.bmi;
  if (v === "Children") return clamp(Math.round(p.children), 0, 5);
  return FACTOR_VALUE[v](p) === part.slice(v.length) ? 1 : 0;
}

const designRow = (m: Glm, p: Profile) =>
  m.terms.map((t) => t.split(":").reduce((x, part) => x * partValue(m, part, p), 1));

const dot = (a: number[], b: number[]) => a.reduce((s, v, i) => s + v * b[i], 0);
const quadForm = (x: number[], V: number[][]) => x.reduce((s, xi, i) => s + xi * dot(V[i], x), 0);

/** Log-scale prediction per policy year and its standard error. */
export function predictLog(which: "frequency" | "severity", p: Profile) {
  const m = which === "frequency" ? FREQUENCY : SEVERITY;
  const x = designRow(m, p);
  return { fit: dot(x, m.coef), se: Math.sqrt(quadForm(x, m.vcov)) };
}

/*
 * Factor groups for the premium build-up. Variables that interact in
 * either model (age and sex in the frequency model) are shown together,
 * so every group's relativity is well defined and the groups multiply
 * back to the premium exactly.
 */
const GROUPS: Variable[][] = (() => {
  const parent = new Map<Variable, Variable>(VARIABLES.map((v) => [v, v]));
  const find = (v: Variable): Variable => (parent.get(v) === v ? v : find(parent.get(v)!));
  for (const m of [FREQUENCY, SEVERITY])
    for (const t of m.terms) {
      const vs = t.split(":").map(variableOf).filter((v): v is Variable => v !== null);
      for (const v of vs.slice(1)) parent.set(find(v), find(vs[0]));
    }
  const groups = new Map<Variable, Variable[]>();
  for (const v of VARIABLES) groups.set(find(v), [...(groups.get(find(v)) ?? []), v]);
  return [...groups.values()];
})();

function groupContributions(m: Glm, p: Profile) {
  const x = designRow(m, p);
  const x0 = designRow(m, BASE);
  const out = GROUPS.map(() => 0);
  m.terms.forEach((t, j) => {
    const v = t.split(":").map(variableOf).find((u) => u !== null);
    if (!v) return;
    out[GROUPS.findIndex((g) => g.includes(v))] += m.coef[j] * (x[j] - x0[j]);
  });
  return out;
}

const describe = (v: Variable, p: Profile) =>
  ({
    Age: `${p.age}`,
    Sex: p.sex,
    BMI: p.bmi.toFixed(1),
    Smoker: p.smoker,
    Children: `${p.children}`,
    Province: p.province,
    Plan: p.plan,
  })[v];

export function quote(p: Profile) {
  const f = predictLog("frequency", p);
  const s = predictLog("severity", p);
  const f0 = predictLog("frequency", BASE).fit;
  const s0 = predictLog("severity", BASE).fit;
  const se = Math.sqrt(f.se ** 2 + s.se ** 2);
  const cf = groupContributions(FREQUENCY, p);
  const cs = groupContributions(SEVERITY, p);
  // The tariff replaces the fitted age and sex factor with the sex's
  // graduated curve, loaded for maternity; smoothing is the ratio of the two.
  const ageSex = GROUPS.findIndex((g) => g.includes("Age"));
  const smoothing = TARIFF[p.sex].tariff[ageIndex(p.age)] / Math.exp(cf[ageSex] + cs[ageSex]);
  return {
    frequency: Math.exp(f.fit),
    severity: Math.exp(s.fit),
    pure: Math.exp(f.fit + s.fit),
    // 95% interval for the expected annual cost. The frequency and severity
    // models are fitted to separate parts of the likelihood, so their
    // estimates are independent and the log-scale variances add.
    se: { frequency: f.se, severity: s.se, pure: se },
    pureLow: Math.exp(f.fit + s.fit - Z95 * se),
    pureHigh: Math.exp(f.fit + s.fit + Z95 * se),
    smoothing,
    tariff: Math.exp(f.fit + s.fit) * smoothing,
    base: { frequency: Math.exp(f0), severity: Math.exp(s0), pure: Math.exp(f0 + s0) },
    factors: GROUPS.map((g, i) => ({
      key: g.join("-"),
      label: g.map((v, j) => (j ? v.toLowerCase() : v)).join(" and "),
      value: g.map((v) => describe(v, p)).join(", "),
      frequency: Math.exp(cf[i]),
      severity: Math.exp(cs[i]),
      combined: Math.exp(cf[i] + cs[i]),
    })),
  };
}

/** Share of holdout members on the same plan (0 to 100) with a lower pure premium. */
export function planPercentile(pure: number, plan: string) {
  const q = (model.portfolio as Record<string, { percentiles: number[] }>)[plan].percentiles;
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
