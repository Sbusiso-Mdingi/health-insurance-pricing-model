// The dashboard must price every profile exactly as R's predict() does.
import { expect, test } from "bun:test";
import cases from "./parity-cases.json";
import { quote, type Profile } from "../src/pricing";

test("frequency, severity and pure premium match R on 300 random profiles", () => {
  for (const c of cases) {
    const p: Profile = {
      age: c.Age,
      bmi: c.BMI,
      sex: c.Sex as Profile["sex"],
      smoker: c.Smoker as Profile["smoker"],
      region: c.Region as Profile["region"],
      children: c.Children,
    };
    const q = quote(p);
    expect(Math.abs(q.frequency / c.frequency - 1)).toBeLessThan(1e-9);
    expect(Math.abs(q.severity / c.severity - 1)).toBeLessThan(1e-9);
    expect(Math.abs(q.pure / c.pure - 1)).toBeLessThan(1e-9);
  }
});

test("factor relativities multiply back to the pure premium", () => {
  const q = quote({ age: 63, bmi: 33.4, sex: "male", smoker: "yes", region: "southeast", children: 3 });
  const product = q.factors.reduce((a, f) => a * f.combined, q.base.pure);
  expect(Math.abs(product / q.pure - 1)).toBeLessThan(1e-12);
});
