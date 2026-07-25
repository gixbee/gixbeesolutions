import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { AuthService } from '../../core/services/auth.service';

interface SystemLog {
  id: string;
  level: 'INFO' | 'WARN' | 'ERROR';
  type: 'API' | 'AUTH' | 'DB' | 'SYSTEM' | 'APP_CRASH';
  method: string | null;
  path: string | null;
  statusCode: number | null;
  durationMs: number | null;
  userId: string | null;
  ip: string | null;
  message: string | null;
  detail: string | null;
  createdAt: string;
}

interface LogsPage {
  data: SystemLog[];
  total: number;
  page: number;
  limit: number;
  pages: number;
}

interface LogStats {
  since: string;
  total: number;
  byType: Record<string, number>;
  byLevel: Record<string, number>;
}

/// System Logs browser: every API call, auth attempt, DB failure and server
/// error recorded by the backend's ApiLoggingInterceptor, filterable by
/// type / level / method / status / text / date range.
@Component({
  selector: 'app-logs',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="gx-page-title">System Logs</div>
    <div class="gx-page-sub">API calls, auth attempts, database failures, server errors and app crashes.</div>

    <!-- 24h summary chips -->
    @if (stats) {
      <div class="d-flex flex-wrap gap-2 mb-3">
        <span class="badge bg-secondary">Last 24h: {{ stats.total }}</span>
        <span class="badge bg-primary" role="button" (click)="quickType('API')">API {{ stats.byType['API'] || 0 }}</span>
        <span class="badge bg-info text-dark" role="button" (click)="quickType('AUTH')">Auth {{ stats.byType['AUTH'] || 0 }}</span>
        <span class="badge bg-dark" role="button" (click)="quickType('DB')">DB {{ stats.byType['DB'] || 0 }}</span>
        <span class="badge text-white" role="button" style="background:#e91e8b" (click)="quickType('APP_CRASH')">App Crashes {{ stats.byType['APP_CRASH'] || 0 }}</span>
        <span class="badge bg-warning text-dark" role="button" (click)="quickLevel('WARN')">Warnings {{ stats.byLevel['WARN'] || 0 }}</span>
        <span class="badge bg-danger" role="button" (click)="quickLevel('ERROR')">Errors {{ stats.byLevel['ERROR'] || 0 }}</span>
        <span class="badge" role="button"
              [class.bg-danger]="problemsOnly"
              [class.bg-outline-danger]="!problemsOnly"
              [class.text-dark]="!problemsOnly"
              [style.border]="!problemsOnly ? '1px solid #dc2626' : null"
              [style.color]="!problemsOnly ? '#dc2626' : null"
              [style.background]="!problemsOnly ? 'transparent' : null"
              (click)="toggleProblems()">
          Problems only
        </span>
        <span class="badge" role="button"
              [class.bg-warning]="slowOnly"
              [class.text-dark]="true"
              [style.border]="!slowOnly ? '1px solid #d97706' : null"
              [style.color]="!slowOnly ? '#d97706' : null"
              [style.background]="!slowOnly ? 'transparent' : null"
              (click)="toggleSlow()">
          Slow (≥1s)
        </span>
      </div>
    }

    <div class="card">
      <div class="card-header py-3">
        <div class="row g-2 align-items-end">
          <div class="col-6 col-md-2">
            <label class="form-label mb-1" style="font-size:12px">Type</label>
            <select class="form-select form-select-sm" [(ngModel)]="f.type" (change)="applyFilters()">
              <option value="">All</option>
              <option value="API">API</option>
              <option value="AUTH">Auth</option>
              <option value="DB">Database</option>
              <option value="SYSTEM">System</option>
              <option value="APP_CRASH">App Crashes</option>
            </select>
          </div>
          <div class="col-6 col-md-2">
            <label class="form-label mb-1" style="font-size:12px">Level</label>
            <select class="form-select form-select-sm" [(ngModel)]="f.level"
                    [disabled]="problemsOnly" (change)="applyFilters()">
              <option value="">All</option>
              <option value="INFO">Info</option>
              <option value="WARN">Warn</option>
              <option value="ERROR">Error</option>
            </select>
          </div>
          <div class="col-6 col-md-2">
            <label class="form-label mb-1" style="font-size:12px">Method</label>
            <select class="form-select form-select-sm" [(ngModel)]="f.method" (change)="applyFilters()">
              <option value="">All</option>
              <option>GET</option>
              <option>POST</option>
              <option>PATCH</option>
              <option>PUT</option>
              <option>DELETE</option>
            </select>
          </div>
          <div class="col-6 col-md-2">
            <label class="form-label mb-1" style="font-size:12px">Status</label>
            <select class="form-select form-select-sm" [(ngModel)]="f.status" (change)="applyFilters()">
              <option value="">All</option>
              <option value="2xx">2xx OK</option>
              <option value="4xx">4xx Client</option>
              <option value="401">401 Unauthorized</option>
              <option value="403">403 Forbidden</option>
              <option value="404">404 Not found</option>
              <option value="5xx">5xx Server</option>
            </select>
          </div>
          <div class="col-12 col-md-4">
            <label class="form-label mb-1" style="font-size:12px">Search path / message</label>
            <input class="form-control form-control-sm" placeholder="e.g. /bookings or timeout"
                   [(ngModel)]="f.search" (keyup.enter)="applyFilters()" />
          </div>
          <div class="col-6 col-md-3">
            <label class="form-label mb-1" style="font-size:12px">From</label>
            <input type="datetime-local" class="form-control form-control-sm"
                   [(ngModel)]="f.from" (change)="applyFilters()" />
          </div>
          <div class="col-6 col-md-3">
            <label class="form-label mb-1" style="font-size:12px">To</label>
            <input type="datetime-local" class="form-control form-control-sm"
                   [(ngModel)]="f.to" (change)="applyFilters()" />
          </div>
          <div class="col-12 col-md-6 d-flex gap-2 justify-content-md-end">
            <div class="form-check align-self-center me-2">
              <input class="form-check-input" type="checkbox" id="autoRef"
                     [(ngModel)]="autoRefresh" (change)="toggleAutoRefresh()" />
              <label class="form-check-label" for="autoRef" style="font-size:13px">Auto-refresh (10s)</label>
            </div>
            <button class="btn btn-sm btn-outline-secondary" (click)="resetFilters()">
              <i class="bi bi-x-circle me-1"></i>Reset
            </button>
            <button class="btn btn-sm btn-outline-primary" (click)="load()">
              <i class="bi bi-arrow-clockwise me-1"></i>Refresh
            </button>
            @if (isSuperAdmin) {
              <button class="btn btn-sm btn-outline-danger" (click)="confirmPurge = true">
                <i class="bi bi-trash me-1"></i>Purge old
              </button>
            }
          </div>
        </div>
      </div>

      <div class="table-responsive">
        <table class="table table-hover align-middle" style="font-size:13px">
          <thead>
            <tr>
              <th style="white-space:nowrap">Time</th>
              <th>Level</th>
              <th>Type</th>
              <th>Method</th>
              <th>Path</th>
              <th>Status</th>
              <th class="text-end">ms</th>
              <th>User / IP</th>
              <th>Message</th>
            </tr>
          </thead>
          <tbody>
            @for (l of logs; track l.id) {
              <tr (click)="openDetail(l)" style="cursor:pointer"
                  [class.table-active]="selected?.id === l.id">
                <td style="white-space:nowrap">{{ l.createdAt | date:'MMM d, HH:mm:ss' }}</td>
                <td>
                  <span class="badge" [ngClass]="{
                    'bg-success': l.level === 'INFO',
                    'bg-warning text-dark': l.level === 'WARN',
                    'bg-danger': l.level === 'ERROR'
                  }">{{ l.level }}</span>
                </td>
                <td>
                  <span class="badge" [ngClass]="{
                    'bg-primary': l.type === 'API',
                    'bg-info text-dark': l.type === 'AUTH',
                    'bg-dark': l.type === 'DB',
                    'bg-secondary': l.type === 'SYSTEM'
                  }" [style.background]="l.type === 'APP_CRASH' ? '#e91e8b' : null"
                     [style.color]="l.type === 'APP_CRASH' ? '#fff' : null">{{ l.type === 'APP_CRASH' ? 'APP CRASH' : l.type }}</span>
                </td>
                <td class="fw-semibold">{{ l.method || '—' }}</td>
                <td style="max-width:280px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap"
                    [title]="l.path || ''">{{ l.path || '—' }}</td>
                <td>
                  <span [class.text-danger]="(l.statusCode || 0) >= 500"
                        [class.text-warning]="(l.statusCode || 0) >= 400 && (l.statusCode || 0) < 500"
                        class="fw-semibold">{{ l.statusCode ?? '—' }}</span>
                </td>
                <td class="text-end"
                    [class.text-danger]="(l.durationMs || 0) >= 1000"
                    [class.text-muted]="(l.durationMs || 0) < 1000">{{ l.durationMs ?? '—' }}</td>
                <td style="font-size:12px">
                  <div>{{ l.userId ? (l.userId | slice:0:8) + '…' : 'anon' }}</div>
                  <div class="text-muted">{{ l.ip || '' }}</div>
                </td>
                <td style="max-width:260px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap"
                    [title]="l.message || ''">{{ l.message || '' }}</td>
              </tr>
            } @empty {
              <tr>
                <td colspan="9">
                  <div class="gx-empty">
                    <i class="bi bi-journal-text"></i>
                    No log entries match these filters.
                  </div>
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>

      <div class="card-footer d-flex justify-content-between align-items-center py-2">
        <span class="text-muted" style="font-size:13px">
          {{ total }} entries · page {{ page }} / {{ pages || 1 }}
        </span>
        <div class="btn-group">
          <button class="btn btn-sm btn-outline-secondary" [disabled]="page <= 1" (click)="go(page - 1)">
            <i class="bi bi-chevron-left"></i>
          </button>
          <button class="btn btn-sm btn-outline-secondary" [disabled]="page >= pages" (click)="go(page + 1)">
            <i class="bi bi-chevron-right"></i>
          </button>
        </div>
      </div>
    </div>

    <!-- Detail drawer -->
    @if (selected) {
      <div class="position-fixed top-0 start-0 w-100 h-100"
           style="background:rgba(15,23,42,.45); z-index:1040"
           (click)="closeDetail()"></div>
      <div class="position-fixed top-0 end-0 h-100 bg-white shadow-lg d-flex flex-column"
           style="width:min(480px,100vw); z-index:1041; border-left:1px solid #e2e8f0">
        <div class="d-flex align-items-center justify-content-between px-3 py-3 border-bottom">
          <div>
            <div class="fw-semibold">Log detail</div>
            <div class="text-muted" style="font-size:12px">{{ selected.createdAt | date:'medium' }}</div>
          </div>
          <button type="button" class="btn btn-sm btn-outline-secondary" (click)="closeDetail()">
            <i class="bi bi-x-lg"></i>
          </button>
        </div>
        <div class="p-3 overflow-auto flex-grow-1" style="font-size:13px">
          <div class="d-flex flex-wrap gap-2 mb-3">
            <span class="badge" [ngClass]="{
              'bg-success': selected.level === 'INFO',
              'bg-warning text-dark': selected.level === 'WARN',
              'bg-danger': selected.level === 'ERROR'
            }">{{ selected.level }}</span>
            <span class="badge" [ngClass]="{
              'bg-primary': selected.type === 'API',
              'bg-info text-dark': selected.type === 'AUTH',
              'bg-dark': selected.type === 'DB',
              'bg-secondary': selected.type === 'SYSTEM'
            }">{{ selected.type }}</span>
            @if (selected.method) {
              <span class="badge bg-light text-dark border">{{ selected.method }}</span>
            }
            @if (selected.statusCode != null) {
              <span class="badge bg-light text-dark border">{{ selected.statusCode }}</span>
            }
            @if (selected.durationMs != null) {
              <span class="badge bg-light text-dark border">{{ selected.durationMs }} ms</span>
            }
          </div>

          <div class="mb-3">
            <div class="text-muted mb-1" style="font-size:11px; text-transform:uppercase; letter-spacing:.04em">Path</div>
            <div class="font-monospace" style="word-break:break-all">{{ selected.path || '—' }}</div>
          </div>

          <div class="mb-3">
            <div class="text-muted mb-1" style="font-size:11px; text-transform:uppercase; letter-spacing:.04em">Message</div>
            <div class="fw-semibold">{{ selected.message || '(no message)' }}</div>
          </div>

          <div class="mb-3">
            <div class="text-muted mb-1" style="font-size:11px; text-transform:uppercase; letter-spacing:.04em">User / IP</div>
            <div>{{ selected.userId || 'anon' }} · {{ selected.ip || '—' }}</div>
          </div>

          <div>
            <div class="text-muted mb-1" style="font-size:11px; text-transform:uppercase; letter-spacing:.04em">Detail / stack</div>
            @if (selected.detail) {
              <pre class="mb-0 p-3 rounded" style="font-size:12px; max-height:55vh; overflow:auto; background:#0f172a; color:#e2e8f0; white-space:pre-wrap; word-break:break-word">{{ selected.detail }}</pre>
            } @else {
              <div class="text-muted">No stack / detail recorded for this entry.</div>
            }
          </div>
        </div>
      </div>
    }

    @if (confirmPurge) {
      <div class="modal fade show" style="display:block; background: rgba(15,23,42,.6)">
        <div class="modal-dialog modal-dialog-centered">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">Purge old logs</h5>
              <button type="button" class="btn-close" (click)="confirmPurge = false"></button>
            </div>
            <div class="modal-body">
              <label class="form-label">Delete entries older than (days)</label>
              <input type="number" class="form-control" [(ngModel)]="purgeDays" min="1" max="365" />
              <div class="text-muted mt-2" style="font-size:13px">
                This permanently removes matching rows from the database.
              </div>
            </div>
            <div class="modal-footer">
              <button class="btn btn-secondary" (click)="confirmPurge = false">Cancel</button>
              <button class="btn btn-danger" [disabled]="purgeDays < 1" (click)="purge()">Purge</button>
            </div>
          </div>
        </div>
      </div>
    }
  `,
})
export class LogsComponent implements OnInit, OnDestroy {
  private http = inject(HttpClient);
  private auth = inject(AuthService);

  logs: SystemLog[] = [];
  stats: LogStats | null = null;
  selected: SystemLog | null = null;

  f = { type: '', level: '', method: '', status: '', search: '', from: '', to: '' };
  problemsOnly = false;
  slowOnly = false;

  page = 1;
  limit = 50;
  total = 0;
  pages = 0;

  autoRefresh = false;
  private timer: ReturnType<typeof setInterval> | null = null;

  confirmPurge = false;
  purgeDays = 30;

  readonly isSuperAdmin = this.auth.isSuperAdmin();

  ngOnInit() {
    this.load();
    this.loadStats();
  }

  ngOnDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  load() {
    const params: Record<string, string> = {
      page: String(this.page),
      limit: String(this.limit),
    };
    if (this.f.type) params['type'] = this.f.type;
    if (this.problemsOnly) {
      params['problems'] = 'true';
    } else if (this.f.level) {
      params['level'] = this.f.level;
    }
    if (this.slowOnly) params['minDurationMs'] = '1000';
    if (this.f.method) params['method'] = this.f.method;
    if (this.f.status) params['status'] = this.f.status;
    if (this.f.search.trim()) params['search'] = this.f.search.trim();
    if (this.f.from) params['from'] = new Date(this.f.from).toISOString();
    if (this.f.to) params['to'] = new Date(this.f.to).toISOString();

    this.http.get<LogsPage>('/api/system-logs/admin', { params }).subscribe((res) => {
      this.logs = res.data;
      this.total = res.total;
      this.page = res.page;
      this.pages = res.pages;
    });
  }

  loadStats() {
    this.http.get<LogStats>('/api/system-logs/admin/stats').subscribe((s) => (this.stats = s));
  }

  applyFilters() {
    this.page = 1;
    this.selected = null;
    this.load();
  }

  resetFilters() {
    this.f = { type: '', level: '', method: '', status: '', search: '', from: '', to: '' };
    this.problemsOnly = false;
    this.slowOnly = false;
    this.applyFilters();
  }

  quickType(t: string) {
    this.f.type = this.f.type === t ? '' : t;
    this.applyFilters();
  }

  quickLevel(l: string) {
    this.problemsOnly = false;
    this.f.level = this.f.level === l ? '' : l;
    this.applyFilters();
  }

  toggleProblems() {
    this.problemsOnly = !this.problemsOnly;
    if (this.problemsOnly) this.f.level = '';
    this.applyFilters();
  }

  toggleSlow() {
    this.slowOnly = !this.slowOnly;
    this.applyFilters();
  }

  go(p: number) {
    this.page = p;
    this.selected = null;
    this.load();
  }

  openDetail(l: SystemLog) {
    this.selected = l;
  }

  closeDetail() {
    this.selected = null;
  }

  toggleAutoRefresh() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    if (this.autoRefresh) {
      this.timer = setInterval(() => {
        this.load();
        this.loadStats();
      }, 10_000);
    }
  }

  purge() {
    this.http
      .delete<{ deleted: number }>('/api/system-logs/admin/purge', {
        params: { olderThanDays: String(this.purgeDays) },
      })
      .subscribe(() => {
        this.confirmPurge = false;
        this.load();
        this.loadStats();
      });
  }
}
