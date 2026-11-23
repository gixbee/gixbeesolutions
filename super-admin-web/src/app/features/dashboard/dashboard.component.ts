import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { User, UserService } from '../../core/services/user.service';
import { AuthService } from '../../core/services/auth.service';

interface DashboardSummary {
  totalUsers: number;
  totalWorkers: number;
  totalBookings: number;
  pendingApprovals: number;
  recentUsers: (User & { profileImageUrl?: string })[];
}

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="gx-page-heading">
      <div>
        <h1 class="gx-page-title">Dashboard</h1>
        <p class="gx-page-sub">Users, bookings and verification requests.</p>
      </div>
      <button class="btn btn-outline-secondary gx-refresh" (click)="load()" [disabled]="loading">
        <i class="bi bi-arrow-clockwise" aria-hidden="true"></i>
        {{ loading ? 'Refreshing…' : 'Refresh' }}
      </button>
    </div>

    @if (error) {
      <div class="alert alert-danger d-flex flex-wrap justify-content-between align-items-center gap-2" role="alert">
        <span>{{ error }}</span>
      </div>
    }

    <section class="gx-metrics" aria-label="Platform totals" [attr.aria-busy]="loading">
      @for (metric of metrics; track metric.key) {
        <div class="gx-stat" [class.gx-stat-attention]="metric.key === 'pendingApprovals'">
          <span class="gx-stat-icon"><i class="bi" [ngClass]="metric.icon" aria-hidden="true"></i></span>
          <div class="label">{{ metric.label }}</div>
          <div class="value">{{ summary ? (summary[metric.key] | number) : '—' }}</div>
          @if (metric.key === 'pendingApprovals' && canAccess('verifications')) {
            <a class="gx-stat-action" routerLink="/verifications">Review requests <i class="bi bi-arrow-up-right" aria-hidden="true"></i></a>
          }
        </div>
      }
    </section>

    <div class="row g-4">
      <section class="col-xl-8" aria-labelledby="registrations-title">
        <div class="card h-100">
          <div class="card-header gx-section-header">
            <div>
              <h2 id="registrations-title">Recent registrations</h2>
              <p>People who recently joined Gixbee.</p>
            </div>
            @if (canAccess('users')) {
              <a routerLink="/users" class="btn btn-sm btn-outline-secondary">View users <i class="bi bi-arrow-right ms-1" aria-hidden="true"></i></a>
            }
          </div>
          <div class="table-responsive">
            <table class="table table-hover align-middle">
              <caption class="visually-hidden">Recent user registrations and verification status</caption>
              <thead><tr><th scope="col">User</th><th scope="col">Phone</th><th scope="col">Joined</th><th scope="col" class="text-end">Verification</th></tr></thead>
              <tbody>
                @if (loading && !summary) {
                  <tr><td colspan="4"><div class="gx-empty" role="status"><span class="spinner-border spinner-border-sm me-2"></span>Loading registrations…</div></td></tr>
                } @else if (error && !summary) {
                  <tr><td colspan="4"><div class="gx-empty">Registrations could not be loaded.</div></td></tr>
                } @else {
                  @for (user of summary?.recentUsers; track user.id) {
                    <tr>
                      <td>
                        <div class="d-flex align-items-center gap-2">
                          <span class="gx-user-avatar" aria-hidden="true">{{ (user.name || 'U').charAt(0).toUpperCase() }}</span>
                          <span class="fw-semibold">{{ user.name || 'Unnamed user' }}</span>
                        </div>
                      </td>
                      <td class="gx-nowrap">{{ user.phoneNumber }}</td>
                      <td class="gx-nowrap">{{ user.createdAt | date:'d MMM, HH:mm' }}</td>
                      <td class="text-end"><span class="badge" [ngClass]="user.isVerified ? 'bg-success' : 'bg-warning'">{{ user.isVerified ? 'Verified' : 'Pending' }}</span></td>
                    </tr>
                  } @empty {
                    <tr><td colspan="4"><div class="gx-empty"><i class="bi bi-people" aria-hidden="true"></i>No registrations yet.</div></td></tr>
                  }
                }
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section class="col-xl-4" aria-labelledby="actions-title">
        <div class="card">
          <div class="card-header gx-section-header"><h2 id="actions-title">Workspace shortcuts</h2></div>
          <div class="gx-quick-actions">
            @for (action of visibleActions; track action.path) {
              <a [routerLink]="action.path" class="gx-quick-action">
                <span class="gx-quick-action-icon"><i class="bi" [ngClass]="action.icon" aria-hidden="true"></i></span>
                <span><strong>{{ action.label }}</strong><small>{{ action.description }}</small></span>
                <i class="bi bi-arrow-up-right" aria-hidden="true"></i>
              </a>
            }
          </div>
        </div>
      </section>
    </div>
  `,
})
export class DashboardComponent implements OnInit {
  private readonly userService = inject(UserService);
  private readonly auth = inject(AuthService);
  summary: DashboardSummary | null = null;
  loading = false;
  error = '';

  readonly metrics: { key: Exclude<keyof DashboardSummary, 'recentUsers'>; label: string; icon: string }[] = [
    { key: 'totalUsers', label: 'Total users', icon: 'bi-people' },
    { key: 'totalWorkers', label: 'Registered workers', icon: 'bi-person-badge' },
    { key: 'totalBookings', label: 'Total bookings', icon: 'bi-calendar-check' },
    { key: 'pendingApprovals', label: 'Awaiting verification', icon: 'bi-patch-check' },
  ];

  readonly visibleActions = [
    { page: 'bookings', path: '/bookings', label: 'Bookings', description: 'View requests and progress', icon: 'bi-calendar-check' },
    { page: 'verifications', path: '/verifications', label: 'Verifications', description: 'Review worker applications', icon: 'bi-patch-check' },
    { page: 'businesses', path: '/businesses', label: 'Businesses', description: 'Review listed businesses', icon: 'bi-shop' },
    { page: 'master-entries', path: '/master-entries', label: 'Master data', description: 'Manage shared app content', icon: 'bi-grid' },
    { page: 'support', path: '/support', label: 'Support', description: 'Respond to support requests', icon: 'bi-life-preserver' },
  ].filter(action => this.auth.canAccess(action.page));

  canAccess(page: string) {
    return this.auth.canAccess(page);
  }

  ngOnInit() {
    this.load();
  }

  load() {
    if (this.loading) return;
    this.loading = true;
    this.error = '';
    this.userService.getSummary().subscribe({
      next: result => {
        this.summary = result;
        this.loading = false;
      },
      error: () => {
        this.error = 'The dashboard could not be refreshed. Try again.';
        this.loading = false;
      },
    });
  }
}
