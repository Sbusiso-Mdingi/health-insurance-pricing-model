import { useMemo, useState } from "react";
import { BarChart, LineChart } from "./charts";
import {
  AGE_RANGE,
  BASE,
  BMI_RANGE,
  MODEL,
  REGIONS,
  portfolioPercentile,
  quote,
  riskClass,
  type Profile,
} from "./pricing";

const money = (v: number) => `R ${Math.round(v).toLocaleString("en-US")}`;
const fixed = (v: number, d = 3) => v.toFixed(d);
const times = (v: number) => `× ${v.toFixed(3)}`;

type Tab = "quote" | "factors" | "validation";

export function App({ embedded }: { embedded: boolean }) {
  const [tab, setTab] = useState<Tab>("quote");
  const tabs: { id: Tab; label: string }[] = [
    { id: "quote", label: "Price a policy" },
    { id: "factors", label: "Rating factors" },
    { id: "validation", label: "Model checks" },
  ];

  return (
    <div className="preview">
      {!embedded && (
        <header className="intro">
          <p className="kicker">Health insurance pricing · Live preview</p>
          <h1>Price a health policy with two GLMs</h1>
          <p>
            A Poisson GLM predicts how often a policyholder claims and a Gamma GLM predicts what
            each claim costs. Change the profile to see the premium, the factors behind it and how
            the models hold up on policies they never saw.
          </p>
        </header>
      )}
      <div className="tabs" role="tablist">
        {tabs.map((t) => (
          <button key={t.id} role="tab" aria-selected={tab === t.id} onClick={() => setTab(t.id)}>
            {t.label}
          </button>
        ))}
      </div>
      <div hidden={tab !== "quote"}>
        <QuoteTab />
      </div>
      <div hidden={tab !== "factors"}>
        <FactorsTab />
      </div>
      <div hidden={tab !== "validation"}>
        <ValidationTab />
      </div>
      <p className="footnote">
        Synthetic data: the premiums are illustrative, not real insurance rates. The models are
        fitted in R; this page applies the exported coefficients and gives the same prices as R.
        {embedded ? "" : " Source: github.com/Sbusiso-Mdingi/health-insurance-pricing-model."}
      </p>
    </div>
  );
}

/* ---------------------------------------------------------------- Quote */

function QuoteTab() {
  const [profile, setProfile] = useState<Profile>({
    age: 45,
    bmi: 27.5,
    sex: "female",
    smoker: "no",
    region: "southeast",
    children: 1,
  });
  const [loading, setLoading] = useState(0.3);
  const set = <K extends keyof Profile>(k: K, v: Profile[K]) => setProfile((p) => ({ ...p, [k]: v }));

  const q = useMemo(() => quote(profile), [profile]);
  const pct = portfolioPercentile(q.pure);
  const risk = riskClass(pct);
  const ageCurve = useMemo(() => {
    const pts: [number, number][] = [];
    for (let a = AGE_RANGE[0]; a <= AGE_RANGE[1]; a++) pts.push([a, quote({ ...profile, age: a }).pure * (1 + loading)]);
    return pts;
  }, [profile, loading]);

  const values: Record<string, string> = {
    age: `${profile.age}`,
    bmi: profile.bmi.toFixed(1),
    sex: profile.sex,
    smoker: profile.smoker,
    children: `${profile.children}`,
    region: profile.region,
  };

  return (
    <div className="quote-grid">
      <section className="panel" aria-label="Policyholder">
        <h3>Policyholder</h3>
        <Slider
          label="Age"
          value={profile.age}
          min={AGE_RANGE[0]}
          max={AGE_RANGE[1]}
          step={1}
          display={`${profile.age}`}
          onChange={(v) => set("age", v)}
        />
        <Slider
          label="BMI"
          value={profile.bmi}
          min={BMI_RANGE[0]}
          max={BMI_RANGE[1]}
          step={0.1}
          display={profile.bmi.toFixed(1)}
          onChange={(v) => set("bmi", Math.round(v * 10) / 10)}
        />
        <Choice label="Sex" options={["female", "male"] as const} value={profile.sex} onChange={(v) => set("sex", v)} />
        <Choice label="Smoker" options={["no", "yes"] as const} value={profile.smoker} onChange={(v) => set("smoker", v)} />
        <Choice
          label="Children"
          options={[0, 1, 2, 3, 4, 5] as const}
          value={profile.children}
          onChange={(v) => set("children", v)}
        />
        <div className="field" role="group" aria-label="Region">
          <span className="field-label">Region</span>
          <div className="region-grid">
            {REGIONS.map((r) => (
              <button key={r} aria-pressed={profile.region === r} onClick={() => set("region", r)}>
                {r}
              </button>
            ))}
          </div>
        </div>
        <Slider
          label="Loading for expenses and profit"
          value={loading}
          min={0}
          max={0.6}
          step={0.01}
          display={`${Math.round(loading * 100)}%`}
          onChange={setLoading}
        />
        <p className="hint">Ages and BMIs are limited to the ranges the models were fitted on.</p>
      </section>

      <div>
        <section className="panel" aria-live="polite">
          <div className="premium">
            <div>
              <p className="tag">Annual premium</p>
              <p className="premium-figure">
                {money(q.pure * (1 + loading))}
                <small>a year</small>
              </p>
            </div>
            <span className={`badge ${risk.tone}`}>{risk.label}</span>
          </div>
          <dl className="stats">
            <div>
              <dt>Claims a year</dt>
              <dd>{fixed(q.frequency)}</dd>
            </div>
            <div>
              <dt>Cost per claim</dt>
              <dd>{money(q.severity)}</dd>
            </div>
            <div>
              <dt>Pure premium</dt>
              <dd>{money(q.pure)}</dd>
            </div>
          </dl>
          <div className="strip">
            <div className="strip-track" aria-hidden="true">
              <i />
              <i />
              <i />
              <i />
              <span className="strip-marker" style={{ left: `${pct}%` }} />
            </div>
            <div className="strip-labels" aria-hidden="true">
              <span>Low</span>
              <span>Moderate</span>
              <span>High</span>
              <span>Very high</span>
            </div>
            <p className="hint">
              A higher pure premium than {Math.round(pct)}% of the {MODEL.validation.holdout.policies.toLocaleString("en-US")}{" "}
              holdout policies. The risk classes are the portfolio's quartiles.
            </p>
          </div>
        </section>

        <h3 className="section-title">How the premium is built</h3>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Step</th>
                <th>Value</th>
                <th className="num">Frequency</th>
                <th className="num">Severity</th>
                <th className="num">Premium</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Base profile</td>
                <td className="muted">age 40, BMI 25</td>
                <td className="num">{fixed(q.base.frequency)}</td>
                <td className="num">{money(q.base.severity)}</td>
                <td className="num">{money(q.base.pure)}</td>
              </tr>
              {q.factors.map((f) => (
                <tr key={f.key}>
                  <td>{f.label}</td>
                  <td style={{ textTransform: "capitalize" }}>{values[f.key]}</td>
                  <td className="num">{times(f.frequency)}</td>
                  <td className="num">{times(f.severity)}</td>
                  <td className="num">{times(f.combined)}</td>
                </tr>
              ))}
              <tr className="total">
                <td>Pure premium</td>
                <td />
                <td className="num">{fixed(q.frequency)}</td>
                <td className="num">{money(q.severity)}</td>
                <td className="num">{money(q.pure)}</td>
              </tr>
              <tr>
                <td>Loading</td>
                <td>{Math.round(loading * 100)}%</td>
                <td />
                <td />
                <td className="num">{times(1 + loading)}</td>
              </tr>
              <tr className="total">
                <td>Annual premium</td>
                <td />
                <td />
                <td />
                <td className="num">{money(q.pure * (1 + loading))}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p className="hint">
          The base profile is a 40-year-old female non-smoker in the northeast with a BMI of 25 and
          no children. Each factor multiplies the base frequency and severity; the premium factor
          is the product of the two.
        </p>

        <h3 className="section-title">Premium by age for this profile</h3>
        <LineChart
          label="Annual premium by age for the chosen profile"
          series={[{ points: ageCurve, color: "var(--gold)" }]}
          marker={[profile.age, q.pure * (1 + loading)]}
          xLabel="Age"
          yMin={0}
          yFormat={(v) => (v >= 1000 ? `R ${v / 1000}k` : `R ${v}`)}
          width={460}
          height={240}
        />
      </div>
    </div>
  );
}

function Slider({
  label,
  value,
  min,
  max,
  step,
  display,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  display: string;
  onChange: (v: number) => void;
}) {
  return (
    <label className="field">
      <span className="field-label">
        {label}
        <output>{display}</output>
      </span>
      <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} />
    </label>
  );
}

function Choice<T extends string | number>({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: readonly T[];
  value: T;
  onChange: (v: T) => void;
}) {
  return (
    <div className="field" role="group" aria-label={label}>
      <span className="field-label">{label}</span>
      <div className="segmented">
        {options.map((o) => (
          <button key={o} aria-pressed={value === o} onClick={() => onChange(o)}>
            {o}
          </button>
        ))}
      </div>
    </div>
  );
}

/* -------------------------------------------------------------- Factors */

type Component = "pure" | "freq" | "sev";

function FactorsTab() {
  const [component, setComponent] = useState<Component>("pure");
  const curve = (fitted: { freq: number[]; sev: number[] }, xs: number[]): [number, number][] =>
    xs.map((x, i) => {
      const log = component === "freq" ? fitted.freq[i] : component === "sev" ? fitted.sev[i] : fitted.freq[i] + fitted.sev[i];
      return [x, Math.exp(log)];
    });
  const ages = MODEL.frequency.age.map((_, i) => AGE_RANGE[0] + i);
  const bmis = MODEL.frequency.bmi.map((_, i) => BMI_RANGE[0] + i / 10);
  const fittedAge = { freq: MODEL.frequency.age, sev: MODEL.severity.age };
  const fittedBmi = { freq: MODEL.frequency.bmi, sev: MODEL.severity.bmi };
  const what = { pure: "pure premium", freq: "claim frequency", sev: "cost per claim" }[component];

  return (
    <>
      <div className="chart-head">
        <h3 className="section-title" style={{ margin: 0 }}>
          Fitted against true effects
        </h3>
        <div className="segmented small inline" role="group" aria-label="Model component">
          {(
            [
              ["pure", "Pure premium"],
              ["freq", "Frequency"],
              ["sev", "Severity"],
            ] as const
          ).map(([id, text]) => (
            <button key={id} aria-pressed={component === id} onClick={() => setComponent(id)}>
              {text}
            </button>
          ))}
        </div>
      </div>
      <p className="hint" style={{ marginTop: 0, marginBottom: 18 }}>
        Because the data is synthetic, the true effect of each factor is known. The gold line is
        the fitted spline; the dashed line is the effect used to generate the data. Both are
        relative to the base profile (age 40, BMI 25).
      </p>
      <div className="two-up">
        <section className="panel">
          <h3>Age, effect on {what}</h3>
          <LineChart
            label={`Fitted and true age relativity for ${what}`}
            series={[
              { points: curve(MODEL.true_curves.age, ages), color: "var(--ink)", dashed: true, width: 1.5 },
              { points: curve(fittedAge, ages), color: "var(--gold)" },
            ]}
            xLabel="Age"
            yFormat={(v) => `× ${v}`}
            height={300}
            width={420}
          />
          <Legend />
        </section>
        <section className="panel">
          <h3>BMI, effect on {what}</h3>
          <LineChart
            label={`Fitted and true BMI relativity for ${what}`}
            series={[
              { points: curve(MODEL.true_curves.bmi, bmis), color: "var(--ink)", dashed: true, width: 1.5 },
              { points: curve(fittedBmi, bmis), color: "var(--gold)" },
            ]}
            xLabel="BMI"
            yFormat={(v) => `× ${v}`}
            height={300}
            width={420}
          />
          <Legend />
        </section>
      </div>

      <h3 className="section-title">Other rating factors</h3>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Factor</th>
              <th>Level</th>
              <th className="num">Frequency</th>
              <th className="num">True</th>
              <th className="num">Severity</th>
              <th className="num">True</th>
            </tr>
          </thead>
          <tbody>
            {MODEL.factors.map((f) => (
              <tr key={f.factor + f.level}>
                <td>{f.factor}</td>
                <td>{f.level}</td>
                <td className="num">
                  {fixed(f.freq)}
                  <span className="ci">
                    {fixed(f.freq_lo)} to {fixed(f.freq_hi)}
                  </span>
                </td>
                <td className="num">{fixed(f.true_freq)}</td>
                <td className="num">
                  {fixed(f.sev)}
                  <span className="ci">
                    {fixed(f.sev_lo)} to {fixed(f.sev_hi)}
                  </span>
                </td>
                <td className="num">{fixed(f.true_sev)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="hint">
        Multiplicative relativities against the base level ({BASE.sex}, non-smoker, {BASE.region}),
        with 95% confidence intervals. Sex has no true effect on either model and region affects
        frequency only through the southeast.
      </p>
    </>
  );
}

function Legend() {
  return (
    <ul className="legend">
      <li>
        <i style={{ background: "var(--gold)" }} />
        Fitted
      </li>
      <li>
        <i className="dashed" />
        True
      </li>
    </ul>
  );
}

/* ----------------------------------------------------------- Validation */

function ValidationTab() {
  const v = MODEL.validation;
  const h = v.holdout;
  const factorName = (f: (typeof MODEL.factors)[number]) =>
    f.factor === "Region" ? `${f.level} region` : f.factor === "Sex" ? f.level : f.factor.toLowerCase();
  const misses = MODEL.factors.flatMap((f) => [
    { name: factorName(f), part: "frequency", est: f.freq, lo: f.freq_lo, hi: f.freq_hi, truth: f.true_freq },
    { name: factorName(f), part: "severity", est: f.sev, lo: f.sev_lo, hi: f.sev_hi, truth: f.true_sev },
  ]).filter((r) => r.truth < r.lo || r.truth > r.hi);
  const lorenz = (l: { x: number[]; y: number[] }): [number, number][] => l.x.map((x, i) => [x * 100, l.y[i] * 100]);

  return (
    <>
      <p className="hint" style={{ marginTop: 0, marginBottom: 18 }}>
        The models were fitted on {v.train_policies.toLocaleString("en-US")} policies and tested on
        the other {h.policies.toLocaleString("en-US")} ({Math.round(h.exposure).toLocaleString("en-US")} policy
        years, {h.claims.toLocaleString("en-US")} claims).
      </p>
      <dl className="stats four stat-cards">
        <div>
          <dt>Actual over expected</dt>
          <dd>
            {fixed(h.cost_ae)}
            <small>holdout claim cost ({fixed(h.claims_ae)} on claim count)</small>
          </dd>
        </div>
        <div>
          <dt>Gini</dt>
          <dd>
            {fixed(h.gini_model)}
            <small>against {fixed(h.gini_true)} for the true model</small>
          </dd>
        </div>
        <div>
          <dt>Poisson dispersion</dt>
          <dd>
            {fixed(MODEL.frequency.dispersion)}
            <small>1 means no overdispersion</small>
          </dd>
        </div>
        <div>
          <dt>Gamma dispersion</dt>
          <dd>
            {fixed(MODEL.severity.dispersion)}
            <small>true squared CV {fixed(Math.exp(0.64) - 1)}</small>
          </dd>
        </div>
      </dl>

      <div className="two-up" style={{ marginTop: 28 }}>
        <section className="panel">
          <h3>Lift by predicted cost band</h3>
          <BarChart
            label="Predicted and actual cost per policy year in ten bands of predicted cost"
            groups={v.lift.map((l) => ({ label: String(l.band), values: [l.predicted, l.actual] }))}
            colors={["var(--gold)", "var(--ink)"]}
            xLabel="Band, lowest to highest predicted cost"
            yFormat={(x) => (x >= 1000 ? `R ${x / 1000}k` : `R ${x}`)}
            width={420}
            height={300}
          />
          <ul className="legend">
            <li>
              <i className="box" style={{ background: "var(--gold)" }} />
              Predicted cost per policy year
            </li>
            <li>
              <i className="box" style={{ background: "var(--ink)" }} />
              Actual
            </li>
          </ul>
        </section>
        <section className="panel">
          <h3>Lorenz curve</h3>
          <LineChart
            label="Share of claim cost against share of exposure, sorted by predicted cost"
            series={[
              { points: [[0, 0], [100, 100]], color: "var(--line)", width: 1.5 },
              { points: lorenz(v.lorenz_model), color: "var(--gold)", width: 3.5 },
              { points: lorenz(v.lorenz_true), color: "var(--ink)", dashed: true, width: 1.5 },
            ]}
            width={420}
            height={300}
            xLabel="Share of exposure, lowest predicted cost first (%)"
            yFormat={(x) => `${x}%`}
            yMin={0}
          />
          <ul className="legend">
            <li>
              <i style={{ background: "var(--gold)" }} />
              Fitted model
            </li>
            <li>
              <i className="dashed" />
              True model
            </li>
            <li>
              <i style={{ background: "var(--line)" }} />
              No rating
            </li>
          </ul>
        </section>
      </div>

      <div className="caveat">
        <p>
          The fitted model ranks risks almost exactly as well as the model that generated the data:
          its Gini is {fixed(h.gini_model)} against {fixed(h.gini_true)}. The frequency model
          explains {(100 * h.freq_deviance_explained).toFixed(1)}% of the Poisson deviance, which
          is normal for claim counts, because most of the difference between two policies' claims
          in a year is chance.
        </p>
        {misses.length > 0 && (
          <p>
            Of the twelve relativity intervals, {misses.length === 1 ? "one misses" : `${misses.length} miss`} the
            true value:{" "}
            {misses
              .map((m) => `${m.name} ${m.part} (fitted ${fixed(m.est)}, true ${fixed(m.truth)})`)
              .join("; ")}
            . With 95% intervals, about one miss in twenty is expected by chance.
          </p>
        )}
      </div>
    </>
  );
}
