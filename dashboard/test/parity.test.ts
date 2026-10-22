// The dashboard must price every profile exactly as R's predict() does,
// and give the same standard errors as R's covariance matrices.
import { expect, test } from "bun:test";
import cases from "./parity-cases.json";
import { quote, type Profile } from "../src/pricing";

const toProfile = (c: (typeof cases)[number]): Profile => ({
  age: c.Age,
  bmi: c.BMI,
  sex: c.Sex as Profile["sex"],
  smoker: c.Smoker as Profile["smoker"],
  province: c.Province,
  plan: c.Plan,
  children: c.Children,
});

test("frequency, severity and pure premium match R on 300 random profiles", () => {
  for (const c of cases) {
    const q = quote(toProfile(c));
    expect(Math.abs(q.frequency / c.frequency - 1)).toBeLessThan(1e-9);
    expect(Math.abs(q.severity / c.severity - 1)).toBeLessThan(1e-9);
    expect(Math.abs(q.pure / c.pure - 1)).toBeLessThan(1e-9);
  }
});

test("standard errors match R on 300 random profiles", () => {
  for (const c of cases) {
    const q = quote(toProfile(c));
    expect(Math.abs(q.se.frequency / c.se_frequency - 1)).toBeLessThan(1e-9);
    expect(Math.abs(q.se.severity / c.se_severity - 1)).toBeLessThan(1e-9);
  }
});

test("tariff premium matches R and never falls with age", () => {
  for (const c of cases) {
    const q = quote(toProfile(c));
    expect(Math.abs(q.tariff / c.tariff - 1)).toBeLessThan(1e-9);
  }
  for (const sex of ["female", "male"] as const) {
    const p = { ...toProfile(cases[0]), sex };
    for (let age = 19; age <= 85; age++)
      expect(quote({ ...p, age }).tariff).toBeGreaterThanOrEqual(quote({ ...p, age: age - 1 }).tariff * (1 - 1e-12));
  }
});

test("factor relativities multiply back to the pure premium", () => {
  for (const c of cases.slice(0, 50)) {
    const q = quote(toProfile(c));
    const product = q.factors.reduce((a, f) => a * f.combined, q.base.pure);
    expect(Math.abs(product / q.pure - 1)).toBeLessThan(1e-12);
  }
});

test("age and sex are grouped because they interact", () => {
  const q = quote(toProfile(cases[0]));
  expect(q.factors.map((f) => f.label)).toEqual([
    "Age and sex",
    "BMI",
    "Smoker",
    "Children",
    "Province",
    "Plan",
  ]);
});
