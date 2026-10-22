import { useMemo, useState } from "react";
import { BarChart, LineChart, type Band } from "./charts";
import coverage from "./coverage.json";
import {
  AGE_RANGE,
  BMI_RANGE,
  MODEL,
  PLANS,
  PROVINCES,
  planPercentile,
  quote,
  riskClass,
  type Profile,
} from "./pricing";

const money = (v: number) => `R ${Math.round(v).toLocaleString("en-US")}`;
const fixed = (v: number, d = 3) => v.toFixed(d);
const times = (v: number) => `× ${v.toFixed(3)}`;
const pct = (v: number, d = 1) => `${(100 * v).toFixed(d)}%`;
const rands = (v: number) => (v >= 1000 ? `R ${v / 1000}k` : `R ${v}`);
const Z95 = 1.96;

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
          <h1>Price a South African health policy with two GLMs</h1>
          <p>
            A negative binomial GLM predicts how often a member claims and a Gamma GLM predicts what
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
        Synthetic data: the premiums are illustrative, not real insurance rates. The
        models are fitted in R; this page applies the exported coefficients and gives the same prices
        and intervals as R.
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
    province: "Gauteng",
    plan: "Standard",
    children: 1,
  });
  const [loading, setLoading] = useState(0.15);
  const set = <K extends keyof Profile>(k: K, v: Profile[K]) => setProfile((p) => ({ ...p, [k]: v }));

  const q = useMemo(() => quote(profile), [profile]);
  const load = 1 + loading;
  const monthly = (annual: number) => (annual * load) / 12;
  const percentile = planPercentile(q.pure, profile.plan);
  const risk = riskClass(percentile);
  const ageCurve = useMemo(() => {
    const line: [number, number][] = [];
    const tariff: [number, number][] = [];
    const band: Band["points"] = [];
    for (let a = AGE_RANGE[0]; a <= AGE_RANGE[1]; a++) {
      const r = quote({ ...profile, age: a });
      line.push([a, monthly(r.pure)]);
      tariff.push([a, monthly(r.tariff)]);
      band.push([a, monthly(r.pureLow), monthly(r.pureHigh)]);
    }
    return { line, tariff, band };
  }, [profile, loading]);

  return (
    <div className="quote-grid">
      <section className="panel" aria-label="Member">
        <h3>Member</h3>
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
        <div className="field" role="group" aria-label="Province">
          <span className="field-label">Province</span>
          <div className="province-grid">
            {PROVINCES.map((r) => (
              <button key={r} aria-pressed={profile.province === r} onClick={() => set("province", r)}>
                {r}
              </button>
            ))}
          </div>
        </div>
        <Choice label="Plan" options={PLANS} value={profile.plan} onChange={(v) => set("plan", v)} />
        <Slider
          label="Loading for expenses"
          value={loading}
          min={0}
          max={0.4}
          step={0.01}
          display={`${Math.round(loading * 100)}%`}
          onChange={setLoading}
        />
        <p className="hint">
          Essential covers in-hospital treatment, Standard adds out-of-hospital specialists, scans
          and tests, and Comprehensive adds GP visits, prescribed medicines, dental and optical. Ages
          and BMIs are limited to the ranges the models were fitted on. The 15% loading is an
          assumption, not a fitted value.
        </p>
      </section>

      <div>
        <section className="panel" aria-live="polite">
          <div className="premium">
            <div>
              <p className="tag">Premium</p>
              <p className="premium-figure">
                {money(monthly(q.tariff))}
                <small>a month</small>
              </p>
              <p className="premium-sub">
                {money(q.tariff * load)} a year. Risk premium {money(monthly(q.pure))} a month, 95% interval{" "}
                {money(monthly(q.pureLow))} to {money(monthly(q.pureHigh))}.
              </p>
            </div>
            <span className={`badge ${risk.tone}`}>{risk.label}</span>
          </div>
          <dl className="stats">
            <div>
              <dt>Claims a year</dt>
              <dd>{fixed(q.frequency, 2)}</dd>
            </div>
            <div>
              <dt>Cost per claim</dt>
              <dd>{money(q.severity)}</dd>
            </div>
            <div>
              <dt>Expected claims cost</dt>
              <dd>
                {money(q.pure)}
                <small>a year, before loading</small>
              </dd>
            </div>
          </dl>
          <div className="strip">
            <div className="strip-track" aria-hidden="true">
              <i />
              <i />
              <i />
              <i />
              <span className="strip-marker" style={{ left: `${percentile}%` }} />
            </div>
            <div className="strip-labels" aria-hidden="true">
              <span>Low</span>
              <span>Moderate</span>
              <span>High</span>
              <span>Very high</span>
            </div>
            <p className="hint">
              A higher expected cost than {Math.round(percentile)}% of holdout members on the {profile.plan} plan.
              The risk classes are the plan's quartiles, because across plans the cost mostly reflects
              the benefits bought.
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
                <th className="num">Cost</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Base profile</td>
                <td className="muted">see below</td>
                <td className="num">{fixed(q.base.frequency)}</td>
                <td className="num">{money(q.base.severity)}</td>
                <td className="num">{money(q.base.pure)}</td>
              </tr>
              {q.factors.map((f) => (
                <tr key={f.key}>
                  <td>{f.label}</td>
                  <td>{f.value}</td>
                  <td className="num">{times(f.frequency)}</td>
                  <td className="num">{times(f.severity)}</td>
                  <td className="num">{times(f.combined)}</td>
                </tr>
              ))}
              <tr className="total">
                <td>Expected claims cost</td>
                <td />
                <td className="num">{fixed(q.frequency)}</td>
                <td className="num">{money(q.severity)}</td>
                <td className="num">{money(q.pure)}</td>
              </tr>
              <tr>
                <td>Tariff age smoothing</td>
                <td>
                  {profile.age}, {profile.sex}
                </td>
                <td />
                <td />
                <td className="num">{times(q.smoothing)}</td>
              </tr>
              <tr>
                <td>Loading</td>
                <td>{Math.round(loading * 100)}%</td>
                <td />
                <td />
                <td className="num">{times(load)}</td>
              </tr>
              <tr className="total">
                <td>Annual premium</td>
                <td />
                <td />
                <td />
                <td className="num">{money(q.tariff * load)}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p className="hint">
          The base profile is a 40-year-old woman in Gauteng on the Essential plan, a non-smoker with a
          BMI of 25 and no children. Each factor multiplies the base frequency and severity. Age and
          sex are shown together because the frequency model lets the age curve differ by sex. The
          interval comes from the two models' coefficient covariance matrices (the delta method on
          the log scale) and covers estimation uncertainty in the expected cost, not the spread of
          one member's claims. The tariff smoothing replaces the fitted age factor with a curve that
          never falls with age, explained below.
        </p>

        <h3 className="section-title">Monthly premium by age for this profile</h3>
        <LineChart
          label="Monthly tariff premium and risk premium by age for the chosen profile, with the risk premium's 95% interval"
          bands={[{ points: ageCurve.band, color: "rgba(224, 164, 73, 0.25)" }]}
          series={[
            { points: ageCurve.line, color: "var(--gold)", dashed: true },
            { points: ageCurve.tariff, color: "var(--ink)" },
          ]}
          marker={[profile.age, monthly(q.tariff)]}
          xLabel="Age"
          yMin={0}
          yFormat={rands}
          width={460}
          height={240}
        />
        <ul className="legend">
          <li>
            <i style={{ background: "var(--ink)" }} />
            Tariff premium
          </li>
          <li>
            <i style={{ background: "repeating-linear-gradient(90deg, var(--gold) 0 5px, transparent 5px 8px)" }} />
            Risk premium, with 95% interval
          </li>
        </ul>
        <p className="hint">
          Women's expected claims rise to a maternity peak around age 31 and dip before rising again,
          so the risk premium is not a sensible rate table. The tariff pools those ages into one level
          that collects the same total premium from women, so women around the peak pay less than
          their expected claims and women in their late thirties pay more: a cross-subsidy between
          ages. Men's risk premium already rises with age and is unchanged.
        </p>
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
type Side = { fit: number[]; se: number[]; true: number[] };
type Curve = { freq: Side; sev: Side };

function FactorsTab() {
  const [component, setComponent] = useState<Component>("pure");
  const ages = MODEL.curves.age.female.freq.fit.map((_, i) => AGE_RANGE[0] + i);
  const bmis = MODEL.curves.bmi.freq.fit.map((_, i) => BMI_RANGE[0] + i / 10);
  const what = { pure: "expected cost", freq: "claim frequency", sev: "cost per claim" }[component];
  const tariffLine = (sex: "female" | "male", which: "risk" | "tariff"): [number, number][] =>
    MODEL.tariff[sex][which]
      .map((v, i): [number, number] => [MODEL.tariff.ages[i], v])
      .filter(([age]) => age <= 55);
  const subsidyBands = [...new Set(MODEL.tariff.cross_subsidy.map((c) => c.band))];

  // Log relativity of the chosen component, fitted with its standard error,
  // and true. The two models are independent, so the variances add.
  const pick = (c: Curve, i: number) => {
    if (component === "freq") return { fit: c.freq.fit[i], se: c.freq.se[i], truth: c.freq.true[i] };
    if (component === "sev") return { fit: c.sev.fit[i], se: c.sev.se[i], truth: c.sev.true[i] };
    return {
      fit: c.freq.fit[i] + c.sev.fit[i],
      se: Math.hypot(c.freq.se[i], c.sev.se[i]),
      truth: c.freq.true[i] + c.sev.true[i],
    };
  };
  const lines = (c: Curve, xs: number[], color: string, band: string) => {
    const r = xs.map((x, i) => [x, pick(c, i)] as const);
    return {
      fitted: { points: r.map(([x, v]): [number, number] => [x, Math.exp(v.fit)]), color },
      truth: { points: r.map(([x, v]): [number, number] => [x, Math.exp(v.truth)]), color: "var(--ink)", dashed: true, width: 1.5 },
      band: {
        points: r.map(([x, v]): [number, number, number] => [x, Math.exp(v.fit - Z95 * v.se), Math.exp(v.fit + Z95 * v.se)]),
        color: band,
      },
    };
  };
  const female = lines(MODEL.curves.age.female as Curve, ages, "var(--gold)", "rgba(224, 164, 73, 0.25)");
  const male = lines(MODEL.curves.age.male as Curve, ages, "var(--green)", "rgba(47, 106, 79, 0.18)");
  const bmi = lines(MODEL.curves.bmi as Curve, bmis, "var(--gold)", "rgba(224, 164, 73, 0.25)");

  return (
    <>
      <div className="chart-head">
        <h3 className="section-title" style={{ margin: 0 }}>
          Fitted against true effects
        </h3>
        <div className="segmented small inline" role="group" aria-label="Model component">
          {(
            [
              ["pure", "Expected cost"],
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
        Because the data is synthetic, the true effect of each factor is known. Solid lines are the
        fitted splines with their 95% bands; dashed lines are the effects used to generate the data.
        All are relative to the base profile, a 40-year-old woman with a BMI of 25. The frequency
        curve for women includes a maternity peak around age 31.
      </p>
      <div className="two-up">
        <section className="panel">
          <h3>Age, effect on {what}</h3>
          <LineChart
            label={`Fitted and true age relativity for ${what}, women and men`}
            bands={[female.band, male.band]}
            series={[female.fitted, male.fitted, female.truth, male.truth]}
            xLabel="Age"
            yFormat={(v) => `× ${v}`}
            height={300}
            width={420}
          />
          <ul className="legend">
            <li>
              <i style={{ background: "var(--gold)" }} />
              Women
            </li>
            <li>
              <i style={{ background: "var(--green)" }} />
              Men
            </li>
            <li>
              <i className="dashed" />
              True
            </li>
          </ul>
        </section>
        <section className="panel">
          <h3>BMI, effect on {what}</h3>
          <LineChart
            label={`Fitted and true BMI relativity for ${what}`}
            bands={[bmi.band]}
            series={[bmi.fitted, bmi.truth]}
            xLabel="BMI"
            yFormat={(v) => `× ${v}`}
            height={300}
            width={420}
          />
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
        </section>
      </div>

      <h3 className="section-title">From risk premium to tariff</h3>
      <div className="two-up">
        <section className="panel">
          <h3>Age and sex factor, ages 18 to 55</h3>
          <LineChart
            label="Fitted age and sex factor and the tariff factor, women and men"
            series={[
              { points: tariffLine("female", "risk"), color: "var(--gold)", dashed: true },
              { points: tariffLine("male", "risk"), color: "var(--green)", dashed: true },
              { points: tariffLine("female", "tariff"), color: "var(--gold)" },
              { points: tariffLine("male", "tariff"), color: "var(--green)" },
            ]}
            xLabel="Age"
            yFormat={(v) => `× ${v}`}
            height={300}
            width={420}
          />
          <ul className="legend">
            <li>
              <i style={{ background: "var(--gold)" }} />
              Women
            </li>
            <li>
              <i style={{ background: "var(--green)" }} />
              Men
            </li>
            <li>
              <i className="dashed" />
              Risk premium, fitted
            </li>
          </ul>
        </section>
        <section className="panel">
          <h3>Cross-subsidy by age</h3>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Age</th>
                  <th className="num">Women</th>
                  <th className="num">Men</th>
                </tr>
              </thead>
              <tbody>
                {subsidyBands.map((band) => (
                  <tr key={band}>
                    <td>{band}</td>
                    {(["female", "male"] as const).map((sex) => {
                      const r = MODEL.tariff.cross_subsidy.find((c) => c.sex === sex && c.band === band)!;
                      const d = (r.ratio - 1) * 100;
                      return (
                        <td key={sex} className="num">
                          {Math.abs(d) < 0.05 ? "0.0%" : `${d > 0 ? "+" : ""}${d.toFixed(1)}%`}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>
      <p className="hint">
        A rate table that falls with age, as the fitted factor for women does after the maternity
        peak, would be hard to justify to members. The tariff is the closest curve to each sex's
        fitted factor that never falls with age (a weighted isotonic regression), weighted by the
        training portfolio's expected claims at each age, so it collects the same total premium from
        each sex. The table shows how much more (+) or less each age band pays than its expected
        claims: women around the peak are subsidised by women in their late thirties and early
        forties.
      </p>

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
                  {f.freq === null ? (
                    <span className="muted">by age</span>
                  ) : (
                    <>
                      {fixed(f.freq)}
                      <span className="ci">
                        {fixed(f.freq_lo!)} to {fixed(f.freq_hi!)}
                      </span>
                    </>
                  )}
                </td>
                <td className="num">{f.true_freq === null ? "" : fixed(f.true_freq)}</td>
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
        Multiplicative relativities against the base level (Gauteng, Essential plan, non-smoker, no
        children), with 95% confidence intervals. The sex effect on frequency depends on age, so it
        is shown in the age chart instead.
      </p>
    </>
  );
}

/* ----------------------------------------------------------- Validation */

function ValidationTab() {
  const v = MODEL.validation;
  const h = v.holdout;
  const c = MODEL.comparison;
  const lorenz = (l: { x: number[]; y: number[] }): [number, number][] => l.x.map((x, i) => [x * 100, l.y[i] * 100]);
  const premiumRows = coverage.models.find((m) => m.model.startsWith("Premium, negative binomial"))!;

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
          <dt>Overdispersion</dt>
          <dd>
            {fixed(MODEL.frequency.poisson_dispersion)}
            <small>
              Poisson dispersion; negative binomial theta {fixed(MODEL.frequency.theta, 2)}, true{" "}
              {fixed(MODEL.frequency.theta_true, 2)}
            </small>
          </dd>
        </div>
        <div>
          <dt>Gamma dispersion</dt>
          <dd>
            {fixed(MODEL.severity.dispersion)}
            <small>true squared CV per claim {fixed(MODEL.severity.dispersion_true)}</small>
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
            yFormat={rands}
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

      <h3 className="section-title">Model comparison</h3>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Pure premium model</th>
              <th className="num">Deviance explained</th>
              <th className="num">Gini</th>
              <th className="num">Actual over expected</th>
            </tr>
          </thead>
          <tbody>
            {c.pure.map((r) => (
              <tr key={r.model}>
                <td>{r.model}</td>
                <td className="num">{pct(r.deviance_explained)}</td>
                <td className="num">{fixed(r.gini)}</td>
                <td className="num">{fixed(r.cost_ae)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="hint">
        Holdout cost per policy year; deviance explained uses the Tweedie deviance with power 1.6.
        F1 and S1 are linear in age and BMI, F2 and S2 use natural splines, F3 adds an age by sex
        interaction to frequency and S3 adds one to severity. The single Tweedie GLM uses the F3
        terms.
      </p>
      <div className="two-up" style={{ marginTop: 18 }}>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Frequency</th>
                <th className="num">AIC</th>
                <th className="num">Deviance explained</th>
              </tr>
            </thead>
            <tbody>
              {c.frequency.map((r) => (
                <tr key={r.model + r.family}>
                  <td>
                    {r.model} {r.family === "negbin" ? "negative binomial" : "Poisson"}
                  </td>
                  <td className="num">{Math.round(r.aic).toLocaleString("en-US")}</td>
                  <td className="num">{pct(r.deviance_explained)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Nested test</th>
                <th className="num">Statistic</th>
                <th className="num">p-value</th>
              </tr>
            </thead>
            <tbody>
              {[...c.nested_tests.frequency, ...c.nested_tests.severity].map((t) => (
                <tr key={t.from}>
                  <td>
                    {t.from} to {t.to}
                  </td>
                  <td className="num">{t.statistic.toFixed(t.statistic > 100 ? 0 : 2)}</td>
                  <td className="num">{t.p < 0.001 ? "< 0.001" : fixed(t.p)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      <p className="hint">
        Training AIC and holdout Poisson deviance; the negative binomial has the same mean as the
        Poisson but a much better likelihood. Terms were added by nested tests at the 5% level
        (likelihood ratio for frequency, F tests with the estimated dispersion for severity), which
        selects {c.final.frequency} and {c.final.severity}.
      </p>

      <h3 className="section-title">Interval coverage</h3>
      <div className="two-up">
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Intervals</th>
                <th className="num">Coverage</th>
                <th className="num">SE ratio</th>
              </tr>
            </thead>
            <tbody>
              {coverage.models.map((m) => (
                <tr key={m.model}>
                  <td>{m.model}</td>
                  <td className="num">{pct(m.overall.coverage)}</td>
                  <td className="num">{fixed(m.overall.se_ratio, 2)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Premium interval</th>
                <th className="num">Coverage</th>
              </tr>
            </thead>
            <tbody>
              {premiumRows.rows.map((r) => (
                <tr key={r.target}>
                  <td>{r.target}</td>
                  <td className="num">{pct(r.coverage)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      <p className="hint">
        Share of 95% intervals containing the true value over {coverage.reps} simulated portfolios of{" "}
        {coverage.policies.toLocaleString("en-US")} policies, refitted each time. The Monte Carlo
        standard error is {(100 * coverage.monte_carlo_se).toFixed(1)} points per row. SE ratio is the
        mean standard error over the spread of the estimates: 1 means the standard errors are the
        right size.
      </p>
      <div className="caveat">
        <p>
          Ignoring overdispersion matters: Poisson standard errors are about 30% too small, and its
          intervals miss the true value about three times as often as they should. The negative
          binomial and Gamma intervals cover close to 95%.
        </p>
        <p>
          The premium intervals are slightly narrow for women in their thirties and forties. The
          intervals only cover estimation error, and the age spline still smooths part of the
          maternity peak in women's claim frequency, a small bias the intervals do not include.
        </p>
      </div>
    </>
  );
}
