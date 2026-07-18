import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdminOpsService, AdminBooking } from '../../core/services/admin-ops.service';

/// Bookings monitor — the ops "is the marketplace working" screen.
/// Status filter + auto-refresh; flags requests stuck in REQUESTED > 2 min
/// (broadcast that nobody accepted yet).
@Component({
  selector: 'app-bookings',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="gx-page-title">Bookings</div>
    <div class="gx-page-sub">Live view of instant requests and jobs across the platform.</div>

    <div class="card">
      <div class="card-header d-flex justify-content-between align-items-center py-3">
        <div class="d-flex gap-2">
          <select class="form-select" style="width: 200px" [(ngModel)]="filter" (change)="load()">
            <option value="">All statuses</option>
            <option value="REQUESTED">Searching (REQUESTED)</option>
            <option value="ACCEPTED,ARRIVED,ACTIVE">In progress</option>
            <option value="COMPLETED">Completed</option>
            <option value="CANCELLED,REJECTED">Cancelled / Rejected</option>
          </select>
        </div>
        <div class="d-flex align-items-center gap-3">
          <div class="form-check form-switch mb-0">
            <input class="form-check-input" type="checkbox" id="autoRef" [(ngModel)]="autoRefresh" (change)="toggleAuto()">
            <label class="form-check-label" for="autoRef" style="font-size: 13px">Auto-refresh</label>
          </div>
          <button class="btn btn-sm btn-outline-primary" (click)="load()">
            <i class="bi bi-arrow-clockwise me-1"></i>Refresh
          </button>
        </div>
      </div>
      <div class="table-responsive">
        <table class="table table-hover align-middle">
          <thead>
            <tr>
              <th>Created</th>
              <th>Service</th>
              <th>Customer</th>
              <th>Pro</th>
              <th>Amount</th>
              <th>Payment</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            @for (b of bookings; track b.id) {
              <tr>
                <td style="white-space: nowrap">{{ b.createdAt | date:'MMM d, HH:mm' }}</td>
                <td>
                  <div class="fw-bold">{{ b.skill || b.type }}</div>
                  <div class="text-muted" style="font-size: 12px; max-width: 220px"
                       [title]="b.description || ''">
                    {{ b.description || b.serviceLocation }}
                  </div>
                </td>
                <td>{{ b.customer?.name || '—' }}</td>
                <td>
                  @if (b.operator) {
                    {{ b.operator.name }}
                  } @else {
                    <span class="text-muted">broadcasting…</span>
                  }
                </td>
                <td>₹{{ b.totalAmount || b.amount }}</td>
                <td>
                  <span class="badge" [ngClass]="b.isPaid ? 'bg-success' : 'bg-secondary'">
                    {{ b.paymentMethod }}{{ b.isPaid ? ' · paid' : '' }}
                  </span>
                </td>
                <td>
                  <span class="badge" [ngClass]="statusClass(b)">{{ b.status }}</span>
                  @if (isStuck(b)) {
                    <span class="badge bg-danger ms-1" title="No pro accepted for over 2 minutes">stuck</span>
                  }
                  @if (b.disputedAt && !b.disputeResolvedAt) {
                    <span class="badge bg-warning ms-1">disputed</span>
                  }
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="7">
                  <div class="gx-empty">
                    <i class="bi bi-calendar-check"></i>
                    No bookings match this filter.
                  </div>
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    </div>
  `
})
export class BookingsComponent implements OnInit, OnDestroy {
  private ops = inject(AdminOpsService);

  bookings: AdminBooking[] = [];
  filter = '';
  autoRefresh = false;
  private timer: any = null;

  ngOnInit() {
    this.load();
  }

  ngOnDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  load() {
    this.ops.getBookings(this.filter || undefined).subscribe(res => {
      this.bookings = res;
    });
  }

  toggleAuto() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    if (this.autoRefresh) {
      this.timer = setInterval(() => this.load(), 10000);
    }
  }

  statusClass(b: AdminBooking) {
    switch (b.status) {
      case 'COMPLETED': return 'bg-success';
      case 'CANCELLED':
      case 'REJECTED': return 'bg-danger';
      case 'REQUESTED':
      case 'PENDING': return 'bg-warning';
      default: return 'bg-info'; // ACCEPTED / ARRIVED / ACTIVE
    }
  }

  isStuck(b: AdminBooking): boolean {
    if (b.status !== 'REQUESTED') return false;
    return Date.now() - new Date(b.createdAt).getTime() > 2 * 60 * 1000;
  }
}
