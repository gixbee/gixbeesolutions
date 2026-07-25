import { Component, Input, OnChanges } from '@angular/core';
import { CommonModule } from '@angular/common';

export interface ChartSeries {
  name: string;
  color: string;
  /** [epochMs, value][] */
  data: [number, number][];
  /** Fill the area under the line. */
  area?: boolean;
}

/**
 * Dependency-free SVG time-series chart (Grafana-style panel).
 * Renders one or more series over a shared time axis with a light grid,
 * y-axis labels and hover-free simplicity — built for 5-10 s polling.
 */
@Component({
  selector: 'app-metric-chart',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="card h-100">
      <div class="card-header py-2 d-flex justify-content-between align-items-center">
        <span class="fw-semibold" style="font-size:13px">{{ title }}</span>
        <span class="d-flex gap-3">
          @for (s of series; track s.name) {
            <span style="font-size:11px" class="text-muted">
              <span [style.background]="s.color"
                    style="display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px"></span>
              {{ s.name }}
            </span>
          }
        </span>
      </div>
      <div class="card-body p-2">
        <svg [attr.viewBox]="'0 0 ' + W + ' ' + H" width="100%" preserveAspectRatio="none"
             style="display:block; height: 180px">
          <!-- horizontal gridlines + y labels -->
          @for (g of grid; track g.y) {
            <line [attr.x1]="PAD_L" [attr.x2]="W - PAD_R" [attr.y1]="g.y" [attr.y2]="g.y"
                  stroke="#e2e8f0" stroke-width="1" />
            <text [attr.x]="PAD_L - 6" [attr.y]="g.y + 4" text-anchor="end"
                  font-size="10" fill="#94a3b8">{{ g.label }}</text>
          }
          <!-- series -->
          @for (p of paths; track p.name) {
            @if (p.areaD) {
              <path [attr.d]="p.areaD" [attr.fill]="p.color" opacity="0.12" />
            }
            <path [attr.d]="p.lineD" fill="none" [attr.stroke]="p.color" stroke-width="1.8"
                  stroke-linejoin="round" stroke-linecap="round" />
          }
          <!-- x labels -->
          @for (x of xLabels; track x.x) {
            <text [attr.x]="x.x" [attr.y]="H - 4" text-anchor="middle"
                  font-size="10" fill="#94a3b8">{{ x.label }}</text>
          }
          @if (empty) {
            <text [attr.x]="W / 2" [attr.y]="H / 2" text-anchor="middle" font-size="12" fill="#94a3b8">
              Collecting data…
            </text>
          }
        </svg>
      </div>
    </div>
  `,
})
export class MetricChartComponent implements OnChanges {
  @Input() title = '';
  @Input() series: ChartSeries[] = [];
  /** Formats a y value into a short label (e.g. '42%', '512 MB'). */
  @Input() yFormat: (v: number) => string = (v) => String(Math.round(v));
  /** Force the y max (e.g. 100 for percentages). Otherwise auto. */
  @Input() yMax?: number;

  readonly W = 640;
  readonly H = 200;
  readonly PAD_L = 46;
  readonly PAD_R = 8;
  readonly PAD_T = 8;
  readonly PAD_B = 18;

  paths: { name: string; color: string; lineD: string; areaD: string | null }[] = [];
  grid: { y: number; label: string }[] = [];
  xLabels: { x: number; label: string }[] = [];
  empty = true;

  ngOnChanges() {
    this.build();
  }

  private build() {
    const all = this.series.flatMap((s) => s.data);
    this.empty = all.length < 2;
    this.paths = [];
    this.grid = [];
    this.xLabels = [];
    if (this.empty) return;

    const tMin = Math.min(...all.map((d) => d[0]));
    const tMax = Math.max(...all.map((d) => d[0]));
    const vMaxData = Math.max(...all.map((d) => d[1]), 0);
    const vMax = this.yMax ?? niceMax(vMaxData);
    const vMin = 0;

    const plotW = this.W - this.PAD_L - this.PAD_R;
    const plotH = this.H - this.PAD_T - this.PAD_B;
    const x = (t: number) =>
      this.PAD_L + (tMax === tMin ? 0 : ((t - tMin) / (tMax - tMin)) * plotW);
    const y = (v: number) =>
      this.PAD_T + plotH - ((Math.min(v, vMax) - vMin) / (vMax - vMin || 1)) * plotH;

    // 4 gridlines.
    for (let i = 0; i <= 4; i++) {
      const v = vMin + ((vMax - vMin) * i) / 4;
      this.grid.push({ y: y(v), label: this.yFormat(v) });
    }

    // 4 time labels.
    for (let i = 0; i <= 3; i++) {
      const t = tMin + ((tMax - tMin) * i) / 3;
      const d = new Date(t);
      const hh = String(d.getHours()).padStart(2, '0');
      const mm = String(d.getMinutes()).padStart(2, '0');
      this.xLabels.push({ x: x(t), label: `${hh}:${mm}` });
    }

    for (const s of this.series) {
      if (s.data.length < 2) continue;
      const pts = s.data.map((d) => `${x(d[0]).toFixed(1)},${y(d[1]).toFixed(1)}`);
      const lineD = 'M' + pts.join(' L');
      let areaD: string | null = null;
      if (s.area) {
        const y0 = (this.PAD_T + plotH).toFixed(1);
        const first = x(s.data[0][0]).toFixed(1);
        const last = x(s.data[s.data.length - 1][0]).toFixed(1);
        areaD = `M${first},${y0} L` + pts.join(' L') + ` L${last},${y0} Z`;
      }
      this.paths.push({ name: s.name, color: s.color, lineD, areaD });
    }
  }
}

/** Round a max up to a friendly value so the top gridline is clean. */
function niceMax(v: number): number {
  if (v <= 0) return 1;
  const pow = Math.pow(10, Math.floor(Math.log10(v)));
  const n = v / pow;
  const nice = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
  return nice * pow;
}
