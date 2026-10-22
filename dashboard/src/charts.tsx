/*
 * Small SVG charts. They scale with their container through the viewBox.
 */
type Point = [number, number];
export type Series = { points: Point[]; color: string; dashed?: boolean; width?: number };
/** A shaded interval: [x, low, high] per point. */
export type Band = { points: [number, number, number][]; color: string };

const PAD = { top: 12, right: 14, bottom: 34, left: 58 };

function ticks(lo: number, hi: number, n = 5) {
  const step0 = (hi - lo) / n;
  const mag = 10 ** Math.floor(Math.log10(step0));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= step0) ?? step0;
  const out: number[] = [];
  for (let v = Math.ceil(lo / step) * step; v <= hi + 1e-9; v += step) out.push(+v.toFixed(10));
  return out;
}

export function LineChart({
  series,
  bands = [],
  height = 260,
  xLabel,
  yFormat = (v) => String(v),
  xFormat = (v) => String(v),
  yMin,
  marker,
  label,
  width: W = 560,
}: {
  width?: number;
  series: Series[];
  bands?: Band[];
  height?: number;
  xLabel?: string;
  yFormat?: (v: number) => string;
  xFormat?: (v: number) => string;
  yMin?: number;
  marker?: Point;
  label: string;
}) {
  const all = [
    ...series.flatMap((s) => s.points),
    ...bands.flatMap((b) => b.points.flatMap(([x, lo, hi]): Point[] => [[x, lo], [x, hi]])),
  ];
  const x0 = Math.min(...all.map((p) => p[0]));
  const x1 = Math.max(...all.map((p) => p[0]));
  const ys = all.map((p) => p[1]);
  const lo = yMin ?? Math.min(...ys);
  const hi = Math.max(...ys);
  const yt = ticks(lo, hi + (hi - lo) * 0.04);
  const y0 = Math.min(lo, yt[0]);
  const y1 = Math.max(hi, yt[yt.length - 1]);
  const sx = (x: number) => PAD.left + ((x - x0) / (x1 - x0)) * (W - PAD.left - PAD.right);
  const sy = (y: number) => height - PAD.bottom - ((y - y0) / (y1 - y0)) * (height - PAD.top - PAD.bottom);
  const path = (pts: Point[]) => pts.map((p, i) => `${i ? "L" : "M"}${sx(p[0]).toFixed(1)},${sy(p[1]).toFixed(1)}`).join("");

  return (
    <svg className="chart" viewBox={`0 0 ${W} ${height}`} role="img" aria-label={label}>
      {yt.map((v) => (
        <g key={v}>
          <line className="grid" x1={PAD.left} x2={W - PAD.right} y1={sy(v)} y2={sy(v)} />
          <text x={PAD.left - 8} y={sy(v) + 4} textAnchor="end">
            {yFormat(v)}
          </text>
        </g>
      ))}
      {ticks(x0, x1, 6).map((v) => (
        <text key={v} x={sx(v)} y={height - PAD.bottom + 16} textAnchor="middle">
          {xFormat(v)}
        </text>
      ))}
      <line className="axis" x1={PAD.left} x2={W - PAD.right} y1={height - PAD.bottom} y2={height - PAD.bottom} />
      {xLabel && (
        <text x={(PAD.left + W - PAD.right) / 2} y={height - 4} textAnchor="middle">
          {xLabel}
        </text>
      )}
      {bands.map((b, i) => (
        <path
          key={i}
          d={path(b.points.map(([x, , hi]) => [x, hi])) + path([...b.points].reverse().map(([x, lo]) => [x, lo])).replace("M", "L") + "Z"}
          fill={b.color}
          stroke="none"
        />
      ))}
      {series.map((s, i) => (
        <path
          key={i}
          d={path(s.points)}
          fill="none"
          stroke={s.color}
          strokeWidth={s.width ?? 2.5}
          strokeDasharray={s.dashed ? "5 4" : undefined}
          strokeLinejoin="round"
        />
      ))}
      {marker && (
        <g>
          <line className="axis" x1={sx(marker[0])} x2={sx(marker[0])} y1={PAD.top} y2={height - PAD.bottom} strokeDasharray="2 3" />
          <circle cx={sx(marker[0])} cy={sy(marker[1])} r={5} fill="var(--ink)" stroke="var(--paper)" strokeWidth={2} />
        </g>
      )}
    </svg>
  );
}

export function BarChart({
  groups,
  colors,
  height = 280,
  yFormat = (v) => String(v),
  xLabel,
  label,
  width: W = 560,
}: {
  width?: number;
  groups: { label: string; values: number[] }[];
  colors: string[];
  height?: number;
  yFormat?: (v: number) => string;
  xLabel?: string;
  label: string;
}) {
  const hi = Math.max(...groups.flatMap((g) => g.values));
  const yt = ticks(0, hi * 1.04);
  const y1 = Math.max(hi, yt[yt.length - 1]);
  const inner = W - PAD.left - PAD.right;
  const gw = inner / groups.length;
  const bw = (gw * 0.72) / colors.length;
  const sy = (y: number) => height - PAD.bottom - (y / y1) * (height - PAD.top - PAD.bottom);

  return (
    <svg className="chart" viewBox={`0 0 ${W} ${height}`} role="img" aria-label={label}>
      {yt.map((v) => (
        <g key={v}>
          <line className="grid" x1={PAD.left} x2={W - PAD.right} y1={sy(v)} y2={sy(v)} />
          <text x={PAD.left - 8} y={sy(v) + 4} textAnchor="end">
            {yFormat(v)}
          </text>
        </g>
      ))}
      {groups.map((g, i) => {
        const gx = PAD.left + i * gw + gw * 0.14;
        return (
          <g key={g.label}>
            {g.values.map((v, j) => (
              <rect key={j} x={gx + j * bw} y={sy(v)} width={bw - 1} height={sy(0) - sy(v)} fill={colors[j]} />
            ))}
            <text x={PAD.left + (i + 0.5) * gw} y={height - PAD.bottom + 16} textAnchor="middle">
              {g.label}
            </text>
          </g>
        );
      })}
      <line className="axis" x1={PAD.left} x2={W - PAD.right} y1={sy(0)} y2={sy(0)} />
      {xLabel && (
        <text x={(PAD.left + W - PAD.right) / 2} y={height - 4} textAnchor="middle">
          {xLabel}
        </text>
      )}
    </svg>
  );
}
