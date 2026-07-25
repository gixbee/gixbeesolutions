import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { MetricChartComponent, ChartSeries } from './metric-chart.component';

interface MetricSample {
  t: number;
  procCpu: number;
  sysCpu: number;
  rss: number;
  heapUsed: number;
  heapTotal: number;
  sysMemUsed: number;
  sysMemTotal: number;
  loopLagMs: number;
  diskFree?: number | null;
  diskTotal?: number | null;
  diskFreePct?: number | null;
}

interface MetricAlert {
  severity: 'warning' | 'critical';
  code: string;
  message: string;
}

interface QueueDepth {
  waiting: number;
  active: number;
  failed: number;
  delayed: number;
}

interface CurrentResponse {
  latest: MetricSample | null;
  meta: {
    node: string;
    pid: number;
    platform: string;
    cores: number;
    hostname: string;
    uptimeSec: number;
    osUptimeSec: number;
    loadAvg: number[];
    env: string;
    sampleIntervalMs: number;
    historyDepthMin: number;
  };
  health?: { postgres: boolean; redis: boolean };
  outbox?: { pending: number; failed: number };
  queues?: { bookings: QueueDepth; outbox: QueueDepth };
  traffic1m?: { errors: number };
  alerts?: MetricAlert[];
}

interface TrafficPoint {
  t: number;
  total: number;
  errors: number;
  warns: number;
  avgMs: number | null;
}

const MB = 1024 * 1024;

/// Monitoring: live CPU / memory / event-loop charts sampled by the backend
/// every 5 s, plus request & error rate derived from system_logs — a
/// Kubernetes-dashboard-style view without any external tooling.
@Component({
  selector: 'app-monitoring',
  standalone: true,
  imports: [CommonModule, FormsModule, MetricChartComponent],
  template: `
    <div class="d-flex justify-content-between align-items-start flex-wrap gap-2">
      <div>
        <div class="gx-page-title">Monitoring</div>
        <div class="gx-page-sub">Live server CPU, memory, event loop and traffic.</div>
      </div>
      <div class="d-flex align-items-center gap-2">
        <select class="form-select form-select-sm" style="width:130px"
                [(ngModel)]="windowMin" (change)="loadAll()">
          <option [ngValue]="15">Last 15 min</option>
          <option [ngValue]="30">Last 30 min</option>
          <option [ngValue]="60">Last 1 h</option>
          <option [ngValue]="180">Last 3 h</option>
        </select>
        <select class="form-select form-select-sm" style="width:110px"
                [(ngModel)]="liveSec" (change)="toggleLive()">
          <option [ngValue]="0">Live: Off</option>
          <option [ngValue]="5">Live: 5s</option>
          <option [ngValue]="10">Live: 10s</option>
          <option [ngValue]="30">Live: 30s</option>
          <option [ngValue]="60">Live: 1m</option>
        </select>
        <button class="btn btn-sm btn-outline-primary" (click)="loadAll()">
          <i class="bi bi-arrow-clockwise"></i>
        </button>
      </div>
    </div>

    <!-- Alerts -->
    @if (alerts.length) {
      <div class="mt-3 d-flex flex-column gap-2">
        @for (a of alerts; track a.code + a.message) {
          <div class="alert mb-0 py-2 px-3 d-flex align-items-center gap-2"
               [class.alert-danger]="a.severity === 'critical'"
               [class.alert-warning]="a.severity === 'warning'"
               style="font-size:13px">
            <i class="bi" [class.bi-exclamation-octagon-fill]="a.severity === 'critical'"
               [class.bi-exclamation-triangle-fill]="a.severity === 'warning'"></i>
            <span class="fw-semibold text-uppercase" style="font-size:11px; letter-spacing:.04em">{{ a.severity }}</span>
            <span>{{ a.message }}</span>
          </div>
        }
      </div>
    } @else if (health) {
      <div class="alert alert-success mt-3 mb-0 py-2 px-3" style="font-size:13px">
        <i class="bi bi-check-circle-fill me-1"></i>No active alerts
      </div>
    }

    <!-- Health + deps -->
    <div class="row g-3 mt-1">
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100">
          <div class="text-muted" style="font-size:12px">Postgres</div>
          <div class="d-flex align-items-center gap-2 mt-1">
            <span class="rounded-circle d-inline-block"
                  [style.background]="health?.postgres ? '#16a34a' : '#dc2626'"
                  style="width:10px;height:10px"></span>
            <span class="fw-bold" [class.text-success]="health?.postgres"
                  [class.text-danger]="health && !health.postgres">
              {{ health ? (health.postgres ? 'Up' : 'Down') : '—' }}
            </span>
          </div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100">
          <div class="text-muted" style="font-size:12px">Redis</div>
          <div class="d-flex align-items-center gap-2 mt-1">
            <span class="rounded-circle d-inline-block"
                  [style.background]="health?.redis ? '#16a34a' : '#dc2626'"
                  style="width:10px;height:10px"></span>
            <span class="fw-bold" [class.text-success]="health?.redis"
                  [class.text-danger]="health && !health.redis">
              {{ health ? (health.redis ? 'Up' : 'Down') : '—' }}
            </span>
          </div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100" [class.border-danger]="(outbox?.failed || 0) > 0">
          <div class="text-muted" style="font-size:12px">Outbox</div>
          <div class="fs-5 fw-bold">
            {{ outbox?.pending ?? '—' }}
            <span style="font-size:12px;font-weight:500" class="text-muted">pending</span>
          </div>
          <div style="font-size:12px"
               [class.text-danger]="(outbox?.failed || 0) > 0"
               [class.fw-semibold]="(outbox?.failed || 0) > 0">
            {{ outbox?.failed ?? '—' }} failed
          </div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-3">
        <div class="card p-3 h-100">
          <div class="text-muted" style="font-size:12px">Bookings queue</div>
          <div style="font-size:13px" class="mt-1">
            <span class="me-2">wait <strong>{{ qLabel(queues?.bookings?.waiting) }}</strong></span>
            <span class="me-2">active <strong>{{ qLabel(queues?.bookings?.active) }}</strong></span>
            <span [class.text-danger]="(queues?.bookings?.failed || 0) > 0">
              failed <strong>{{ qLabel(queues?.bookings?.failed) }}</strong>
            </span>
          </div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-3">
        <div class="card p-3 h-100">
          <div class="text-muted" style="font-size:12px">Outbox queue</div>
          <div style="font-size:13px" class="mt-1">
            <span class="me-2">wait <strong>{{ qLabel(queues?.outbox?.waiting) }}</strong></span>
            <span class="me-2">active <strong>{{ qLabel(queues?.outbox?.active) }}</strong></span>
            <span [class.text-danger]="(queues?.outbox?.failed || 0) > 0">
              failed <strong>{{ qLabel(queues?.outbox?.failed) }}</strong>
            </span>
          </div>
        </div>
      </div>
    </div>

    <!-- Stat cards -->
    <div class="row g-3 mt-1">
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100">
          <div class="text-muted" style="font-size:12px">Process CPU</div>
          <div class="fs-4 fw-bold" [class.text-danger]="(latest?.procCpu || 0) > 80">
            {{ latest?.procCpu ?? '—' }}<span style="font-size:14px">%</span>
          </div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100">
          <div class="text-muted" style="font-size:12px">System CPU</div>
          <div class="fs-4 fw-bold" [class.text-danger]="(latest?.sysCpu || 0) > 85">
            {{ latest?.sysCpu ?? '—' }}<span style="font-size:14px">%</span>
          </div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100">
          <div class="text-muted" style="font-size:12px">Process RSS</div>
          <div class="fs-4 fw-bold">{{ mb(latest?.rss) }}<span style="font-size:14px"> MB</span></div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100">
          <div class="text-muted" style="font-size:12px">Heap</div>
          <div class="fs-4 fw-bold">{{ mb(latest?.heapUsed) }}<span style="font-size:14px"> / {{ mb(latest?.heapTotal) }} MB</span></div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100"
             [class.border-warning]="sysMemPctNum > 85">
          <div class="text-muted" style="font-size:12px">System memory</div>
          <div class="fs-4 fw-bold" [class.text-danger]="sysMemPctNum > 85">{{ sysMemPct }}<span style="font-size:14px">%</span></div>
          <div class="text-muted" style="font-size:11px">{{ gb(latest?.sysMemUsed) }} / {{ gb(latest?.sysMemTotal) }} GB</div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100">
          <div class="text-muted" style="font-size:12px">Event-loop lag</div>
          <div class="fs-4 fw-bold" [class.text-danger]="(latest?.loopLagMs || 0) > 100">
            {{ latest?.loopLagMs ?? '—' }}<span style="font-size:14px"> ms</span>
          </div>
        </div>
      </div>
      <div class="col-6 col-md-3 col-xl-2">
        <div class="card p-3 h-100"
             [class.border-danger]="diskFreePctNum != null && diskFreePctNum < 15">
          <div class="text-muted" style="font-size:12px">Disk free</div>
          <div class="fs-4 fw-bold"
               [class.text-danger]="diskFreePctNum != null && diskFreePctNum < 15">
            {{ diskFreePct }}<span style="font-size:14px">%</span>
          </div>
          <div class="text-muted" style="font-size:11px">
            {{ gb(latest?.diskFree) }} / {{ gb(latest?.diskTotal) }} GB free
          </div>
        </div>
      </div>
    </div>

    <!-- Charts -->
    <div class="row g-3 mt-1">
      <div class="col-12 col-xl-6">
        <app-metric-chart title="CPU utilization" [series]="cpuSeries"
                          [yMax]="100" [yFormat]="pctFmt" />
      </div>
      <div class="col-12 col-xl-6">
        <app-metric-chart title="Memory" [series]="memSeries" [yFormat]="mbFmt" />
      </div>
      <div class="col-12 col-xl-6">
        <app-metric-chart title="Requests per minute" [series]="trafficSeries" [yFormat]="intFmt" />
      </div>
      <div class="col-12 col-xl-6">
        <app-metric-chart title="Avg response time & event-loop lag" [series]="latencySeries" [yFormat]="msFmt" />
      </div>
    </div>

    <!-- Host info -->
    @if (meta) {
      <div class="card mt-3 p-3">
        <div class="row" style="font-size:13px">
          <div class="col-6 col-md-3"><span class="text-muted">Host:</span> {{ meta.hostname }}</div>
          <div class="col-6 col-md-3"><span class="text-muted">Platform:</span> {{ meta.platform }} · {{ meta.cores }} cores</div>
          <div class="col-6 col-md-2"><span class="text-muted">Node:</span> {{ meta.node }} (pid {{ meta.pid }})</div>
          <div class="col-6 col-md-2"><span class="text-muted">Env:</span> {{ meta.env }}</div>
          <div class="col-6 col-md-2"><span class="text-muted">App uptime:</span> {{ uptime(meta.uptimeSec) }}</div>
          <div class="col-6 col-md-3 mt-1"><span class="text-muted">Load avg (1/5/15m):</span> {{ meta.loadAvg.join(' / ') }}</div>
          <div class="col-6 col-md-3 mt-1"><span class="text-muted">OS uptime:</span> {{ uptime(meta.osUptimeSec) }}</div>
          <div class="col-6 col-md-3 mt-1"><span class="text-muted">History kept:</span> {{ meta.historyDepthMin }} min (in-memory)</div>
          <div class="col-6 col-md-3 mt-1"><span class="text-muted">ERROR (1m):</span> {{ traffic1m?.errors ?? '—' }}</div>
        </div>
      </div>
    }
  `,
})
export class MonitoringComponent implements OnInit, OnDestroy {
  private http = inject(HttpClient);

  latest: MetricSample | null = null;
  meta: CurrentResponse['meta'] | null = null;
  health: CurrentResponse['health'] | null = null;
  outbox: CurrentResponse['outbox'] | null = null;
  queues: CurrentResponse['queues'] | null = null;
  traffic1m: CurrentResponse['traffic1m'] | null = null;
  alerts: MetricAlert[] = [];

  cpuSeries: ChartSeries[] = [];
  memSeries: ChartSeries[] = [];
  trafficSeries: ChartSeries[] = [];
  latencySeries: ChartSeries[] = [];

  windowMin = 30;
  /// Auto-refresh interval in seconds; 0 = off. Backend samples every 5 s,
  /// so 5 s is the fastest useful setting.
  liveSec = 10;
  private timer: ReturnType<typeof setInterval> | null = null;

  readonly pctFmt = (v: number) => `${Math.round(v)}%`;
  readonly mbFmt = (v: number) => `${Math.round(v)} MB`;
  readonly msFmt = (v: number) => `${Math.round(v)} ms`;
  readonly intFmt = (v: number) => String(Math.round(v));

  get sysMemPct(): string {
    if (!this.latest) return '—';
    return String(
      Math.round((this.latest.sysMemUsed / this.latest.sysMemTotal) * 100),
    );
  }

  get sysMemPctNum(): number {
    if (!this.latest?.sysMemTotal) return 0;
    return (this.latest.sysMemUsed / this.latest.sysMemTotal) * 100;
  }

  get diskFreePct(): string {
    const p = this.latest?.diskFreePct;
    return p == null ? '—' : String(Math.round(p));
  }

  get diskFreePctNum(): number | null {
    return this.latest?.diskFreePct ?? null;
  }

  ngOnInit() {
    this.loadAll();
    this.toggleLive();
  }

  ngOnDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  toggleLive() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    if (this.liveSec > 0) {
      this.timer = setInterval(() => this.loadAll(), this.liveSec * 1000);
    }
  }

  loadAll() {
    this.http
      .get<CurrentResponse>('/api/system-metrics/admin/current')
      .subscribe((res) => {
        this.latest = res.latest;
        this.meta = res.meta;
        this.health = res.health ?? null;
        this.outbox = res.outbox ?? null;
        this.queues = res.queues ?? null;
        this.traffic1m = res.traffic1m ?? null;
        this.alerts = res.alerts ?? [];
      });

    this.http
      .get<{ points: MetricSample[] }>('/api/system-metrics/admin/history', {
        params: { minutes: String(this.windowMin) },
      })
      .subscribe((res) => {
        const p = res.points;
        const pt = (t: number, v: number): [number, number] => [t, v];
        this.cpuSeries = [
          { name: 'Process', color: '#2563eb', area: true, data: p.map((s) => pt(s.t, s.procCpu)) },
          { name: 'System', color: '#f59e0b', data: p.map((s) => pt(s.t, s.sysCpu)) },
        ];
        this.memSeries = [
          { name: 'RSS', color: '#7c3aed', area: true, data: p.map((s) => pt(s.t, s.rss / MB)) },
          { name: 'Heap used', color: '#059669', data: p.map((s) => pt(s.t, s.heapUsed / MB)) },
        ];
        // Latency chart gets loop lag from samples; avg response merged below.
        this.latencySeries = [
          {
            name: 'Event-loop lag',
            color: '#dc2626',
            data: p.map((s) => pt(s.t, s.loopLagMs)),
          },
          ...this.latencySeries.filter((s) => s.name === 'Avg response'),
        ];
      });

    this.http
      .get<{ points: TrafficPoint[] }>('/api/system-metrics/admin/traffic', {
        params: { minutes: String(this.windowMin) },
      })
      .subscribe((res) => {
        const p = res.points;
        const pt = (t: number, v: number): [number, number] => [t, v];
        this.trafficSeries = [
          { name: 'Requests', color: '#2563eb', area: true, data: p.map((x) => pt(x.t, x.total)) },
          { name: '4xx', color: '#f59e0b', data: p.map((x) => pt(x.t, x.warns)) },
          { name: '5xx errors', color: '#dc2626', data: p.map((x) => pt(x.t, x.errors)) },
        ];
        this.latencySeries = [
          ...this.latencySeries.filter((s) => s.name === 'Event-loop lag'),
          {
            name: 'Avg response',
            color: '#0891b2',
            data: p.filter((x) => x.avgMs != null).map((x) => pt(x.t, x.avgMs as number)),
          },
        ];
      });
  }

  qLabel(v?: number | null): string {
    if (v == null || v < 0) return '—';
    return String(v);
  }

  mb(v?: number | null): string {
    return v == null ? '—' : String(Math.round(v / MB));
  }

  gb(v?: number | null): string {
    return v == null ? '—' : (v / (1024 * MB)).toFixed(1);
  }

  uptime(sec: number): string {
    const d = Math.floor(sec / 86400);
    const h = Math.floor((sec % 86400) / 3600);
    const m = Math.floor((sec % 3600) / 60);
    return d > 0 ? `${d}d ${h}h` : h > 0 ? `${h}h ${m}m` : `${m}m`;
  }
}
