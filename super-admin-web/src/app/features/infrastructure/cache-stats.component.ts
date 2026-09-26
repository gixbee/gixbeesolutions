import { Component, inject, OnDestroy, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';

interface DomainStats {
  requests: number;
  cacheHits: number;
  notModified: number;
  dbLoads: number;
  fallbacks: number;
  servedFromCache: number;
  cacheHitRatio: number;
  dbLoadRatio: number;
}

interface CacheStatsResponse {
  uptimeSecs: number;
  hostname: string;
  redisReady: boolean;
  aggregated?: boolean;
  note: string;
  totals: DomainStats;
  byDomain: Record<string, DomainStats>;
}

const DOMAIN_LABELS: Record<string, string> = {
  hiring_master: 'Hiring master',
  location_master: 'Location search',
  service_master: 'Service master',
  public_listings: 'Public listings',
  ephemeral: 'Hiring estimate (ephemeral)',
  user_scoped: 'User-scoped reads',
};

@Component({
  selector: 'app-cache-stats',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="p-3 h-100 overflow-auto bg-dark text-light">
      <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 mb-3">
        <div>
          <div class="fw-bold fs-5">Cache vs DB (read-through)</div>
          <div class="text-secondary small">{{ stats()?.note }}</div>
        </div>
        <div class="d-flex gap-2 align-items-center">
          <span class="badge" [class.bg-success]="stats()?.redisReady" [class.bg-danger]="!stats()?.redisReady">
            Redis {{ stats()?.redisReady ? 'ready' : 'down' }}
          </span>
          <span class="badge bg-primary-subtle text-primary border border-primary-subtle" *ngIf="stats()?.aggregated">
            Cluster-wide
          </span>
          <span class="text-secondary small" *ngIf="stats()">
            Since reset · {{ formatUptime(stats()!.uptimeSecs) }}
            <span class="opacity-75">(API replica {{ stats()!.hostname }})</span>
          </span>
          <button class="btn btn-sm btn-outline-light" (click)="load()" [disabled]="loading()">
            Refresh
          </button>
          <button class="btn btn-sm btn-outline-warning" (click)="reset()" [disabled]="loading()">
            Reset counters
          </button>
        </div>
      </div>

      <div *ngIf="error()" class="alert alert-danger py-2">{{ error() }}</div>
      <div *ngIf="loading() && !stats()" class="text-secondary">Loading stats…</div>

      <ng-container *ngIf="stats() as s">
        <div class="row g-3 mb-4">
          <div class="col-md-4">
            <div class="card bg-black border-secondary h-100">
              <div class="card-body">
                <div class="text-secondary small text-uppercase fw-bold">Cache hit ratio</div>
                <div class="display-6 text-success">{{ pct(s.totals.cacheHitRatio) }}</div>
                <div class="small text-secondary">
                  {{ s.totals.servedFromCache | number }} / {{ s.totals.requests | number }} requests
                </div>
                <div class="progress mt-2" style="height: 8px">
                  <div class="progress-bar bg-success" [style.width.%]="s.totals.cacheHitRatio * 100"></div>
                </div>
              </div>
            </div>
          </div>
          <div class="col-md-4">
            <div class="card bg-black border-secondary h-100">
              <div class="card-body">
                <div class="text-secondary small text-uppercase fw-bold">DB load ratio</div>
                <div class="display-6 text-warning">{{ pct(s.totals.dbLoadRatio) }}</div>
                <div class="small text-secondary">
                  {{ s.totals.dbLoads | number }} loader runs (PostgreSQL payload fetch)
                </div>
                <div class="progress mt-2" style="height: 8px">
                  <div class="progress-bar bg-warning" [style.width.%]="s.totals.dbLoadRatio * 100"></div>
                </div>
              </div>
            </div>
          </div>
          <div class="col-md-4">
            <div class="card bg-black border-secondary h-100">
              <div class="card-body">
                <div class="text-secondary small text-uppercase fw-bold">304 Not Modified</div>
                <div class="display-6 text-info">{{ s.totals.notModified | number }}</div>
                <div class="small text-secondary">Client ETag matched — no body sent</div>
                <div class="small text-secondary mt-1">Fallback loads: {{ s.totals.fallbacks | number }}</div>
              </div>
            </div>
          </div>
        </div>

        <div class="table-responsive border border-secondary rounded">
          <table class="table table-dark table-sm mb-0 align-middle">
            <thead>
              <tr class="text-secondary small">
                <th>Domain</th>
                <th class="text-end">Requests</th>
                <th class="text-end">Cache hits</th>
                <th class="text-end">304</th>
                <th class="text-end">DB loads</th>
                <th class="text-end">Hit %</th>
                <th class="text-end">DB %</th>
              </tr>
            </thead>
            <tbody>
              <tr *ngFor="let row of domainRows(s)">
                <td>{{ row.label }}</td>
                <td class="text-end">{{ row.stats.requests | number }}</td>
                <td class="text-end text-success">{{ row.stats.cacheHits | number }}</td>
                <td class="text-end text-info">{{ row.stats.notModified | number }}</td>
                <td class="text-end text-warning">{{ row.stats.dbLoads | number }}</td>
                <td class="text-end text-light fw-semibold">{{ pct(row.stats.cacheHitRatio) }}</td>
                <td class="text-end text-light fw-semibold">{{ pct(row.stats.dbLoadRatio) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </ng-container>
    </div>
  `,
})
export class CacheStatsComponent implements OnInit, OnDestroy {
  private http = inject(HttpClient);
  private timer: ReturnType<typeof setInterval> | null = null;

  stats = signal<CacheStatsResponse | null>(null);
  loading = signal(false);
  error = signal<string | null>(null);

  ngOnInit() {
    this.load();
    this.timer = setInterval(() => this.load(), 5000);
  }

  ngOnDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  load() {
    this.loading.set(true);
    this.http.get<CacheStatsResponse>('/api/cache/admin/stats').subscribe({
      next: (res) => {
        this.stats.set(res);
        this.error.set(null);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.message || 'Could not load cache stats (Rust API required).');
        this.loading.set(false);
      },
    });
  }

  reset() {
    if (!confirm('Reset cluster cache counters in Redis?')) return;
    this.http.post('/api/cache/admin/stats/reset', {}).subscribe({
      next: () => this.load(),
      error: () => this.error.set('Reset failed'),
    });
  }

  pct(ratio: number): string {
    return `${(ratio * 100).toFixed(1)}%`;
  }

  formatUptime(secs: number): string {
    if (secs < 3600) return `${Math.floor(secs / 60)}m`;
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    return `${h}h ${m}m`;
  }

  domainRows(s: CacheStatsResponse): { key: string; label: string; stats: DomainStats }[] {
    const order = Object.keys(DOMAIN_LABELS);
    return order
      .filter((key) => s.byDomain[key])
      .map((key) => ({
        key,
        label: DOMAIN_LABELS[key] ?? key,
        stats: s.byDomain[key],
      }))
      .sort((a, b) => b.stats.requests - a.stats.requests);
  }
}
