import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdminOpsService, AdminBooking } from '../../core/services/admin-ops.service';

/// Dispute review: reports filed from the app (customer or worker) land on the
/// booking; this page lists them with full context and closes them with a
/// resolution note (both parties get notified).
@Component({
  selector: 'app-disputes',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="gx-page-title">Disputes & Reports</div>
    <div class="gx-page-sub">Reports filed by customers and pros during or after jobs.</div>

    <div class="card">
      <div class="card-header d-flex justify-content-between align-items-center py-3">
        <div class="form-check form-switch mb-0">
          <input class="form-check-input" type="checkbox" id="openOnly" [(ngModel)]="openOnly" (change)="load()">
          <label class="form-check-label" for="openOnly">Unresolved only</label>
        </div>
        <button class="btn btn-sm btn-outline-primary" (click)="load()">
          <i class="bi bi-arrow-clockwise me-1"></i>Refresh
        </button>
      </div>
      <div class="table-responsive">
        <table class="table table-hover align-middle">
          <thead>
            <tr>
              <th>Filed</th>
              <th>Reporter</th>
              <th>Reason</th>
              <th>Booking</th>
              <th>Parties</th>
              <th>Status</th>
              <th class="text-end">Actions</th>
            </tr>
          </thead>
          <tbody>
            @for (d of disputes; track d.id) {
              <tr>
                <td style="white-space: nowrap">{{ d.disputedAt | date:'MMM d, HH:mm' }}</td>
                <td>
                  <span class="badge" [ngClass]="d.disputeReporterRole === 'CUSTOMER' ? 'bg-info' : 'bg-secondary'">
                    {{ d.disputeReporterRole }}
                  </span>
                </td>
                <td style="max-width: 280px">{{ d.disputeReason }}</td>
                <td>
                  <div class="fw-bold">{{ d.skill }} · ₹{{ d.totalAmount || d.amount }}</div>
                  <div class="text-muted" style="font-size: 12px">{{ d.status }} · {{ d.serviceLocation }}</div>
                </td>
                <td style="font-size: 12.5px">
                  <div><span class="text-muted">C:</span> {{ d.customer?.name || '—' }}</div>
                  <div><span class="text-muted">W:</span> {{ d.operator?.name || '—' }}</div>
                </td>
                <td>
                  @if (d.disputeResolvedAt) {
                    <span class="badge bg-success">Resolved</span>
                  } @else {
                    <span class="badge bg-warning">Open</span>
                  }
                </td>
                <td class="text-end">
                  @if (!d.disputeResolvedAt) {
                    <button class="btn btn-sm btn-primary" (click)="openResolve(d)">Resolve</button>
                  } @else {
                    <span class="text-muted" style="font-size: 12px">{{ d.disputeResolution }}</span>
                  }
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="7">
                  <div class="gx-empty">
                    <i class="bi bi-flag"></i>
                    No {{ openOnly ? 'open ' : '' }}disputes. All clear.
                  </div>
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    </div>

    <!-- Resolve modal -->
    @if (resolving) {
      <div class="modal fade show" style="display:block; background: rgba(15,23,42,.6)">
        <div class="modal-dialog modal-dialog-centered">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">Resolve report</h5>
              <button type="button" class="btn-close" (click)="resolving = null"></button>
            </div>
            <div class="modal-body">
              <p class="text-muted" style="font-size: 13px">
                "{{ resolving.disputeReason }}" — filed by {{ resolving.disputeReporterRole?.toLowerCase() }}
              </p>
              <label class="form-label">Resolution note (sent to both parties as "reviewed")</label>
              <textarea class="form-control" rows="3" [(ngModel)]="resolutionNote"
                        placeholder="e.g. Spoke to both parties; refunded visit fee."></textarea>
            </div>
            <div class="modal-footer">
              <button class="btn btn-secondary" (click)="resolving = null">Cancel</button>
              <button class="btn btn-primary" [disabled]="!resolutionNote.trim()" (click)="resolve()">
                Mark resolved
              </button>
            </div>
          </div>
        </div>
      </div>
    }
  `
})
export class DisputesComponent implements OnInit {
  private ops = inject(AdminOpsService);

  disputes: AdminBooking[] = [];
  openOnly = true;
  resolving: AdminBooking | null = null;
  resolutionNote = '';

  ngOnInit() {
    this.load();
  }

  load() {
    this.ops.getDisputes(this.openOnly).subscribe(res => {
      this.disputes = res;
    });
  }

  openResolve(d: AdminBooking) {
    this.resolving = d;
    this.resolutionNote = '';
  }

  resolve() {
    if (!this.resolving) return;
    this.ops.resolveDispute(this.resolving.id, this.resolutionNote.trim()).subscribe(() => {
      this.resolving = null;
      this.load();
    });
  }
}
