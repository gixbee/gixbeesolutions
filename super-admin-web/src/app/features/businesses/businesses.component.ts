import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdminOpsService, AdminBusiness } from '../../core/services/admin-ops.service';

/// Business moderation: listings created from the app land as PENDING with an
/// optional registration/tax document; verify or reject them here.
@Component({
  selector: 'app-businesses',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="gx-page-title">Businesses</div>
    <div class="gx-page-sub">Review and moderate business listings.</div>

    <div class="card">
      <div class="card-header d-flex justify-content-between align-items-center py-3">
        <select class="form-select" style="width: 180px" [(ngModel)]="filter" (change)="load()">
          <option value="PENDING">Pending</option>
          <option value="VERIFIED">Verified</option>
          <option value="REJECTED">Rejected</option>
          <option value="">All</option>
        </select>
        <button class="btn btn-sm btn-outline-primary" (click)="load()">
          <i class="bi bi-arrow-clockwise me-1"></i>Refresh
        </button>
      </div>
      <div class="table-responsive">
        <table class="table table-hover align-middle">
          <thead>
            <tr>
              <th>Business</th>
              <th>Type</th>
              <th>Owner</th>
              <th>Location</th>
              <th>Document</th>
              <th>Status</th>
              <th class="text-end">Actions</th>
            </tr>
          </thead>
          <tbody>
            @for (b of businesses; track b.id) {
              <tr>
                <td>
                  <div class="fw-bold">{{ b.name }}</div>
                  <div class="text-muted" style="font-size: 12px; max-width: 240px">{{ b.description || '' }}</div>
                </td>
                <td><span class="badge bg-secondary">{{ b.type }}</span></td>
                <td>
                  <div>{{ b.owner?.name || '—' }}</div>
                  <div class="text-muted" style="font-size: 12px">{{ b.owner?.phoneNumber || '' }}</div>
                </td>
                <td style="max-width: 180px">{{ b.location || '—' }}</td>
                <td>
                  @if (b.documentUrl) {
                    <img class="gx-doc-thumb" [src]="'/api' + b.documentUrl" (click)="previewUrl = '/api' + b.documentUrl" alt="document">
                  } @else {
                    <span class="text-muted">None</span>
                  }
                </td>
                <td>
                  <span class="badge" [ngClass]="{
                    'bg-warning': b.status === 'PENDING',
                    'bg-success': b.status === 'VERIFIED',
                    'bg-danger': b.status === 'REJECTED'
                  }">{{ b.status }}</span>
                </td>
                <td class="text-end" style="white-space: nowrap">
                  @if (b.status !== 'VERIFIED') {
                    <button class="btn btn-sm btn-primary me-2" (click)="decide(b, 'VERIFIED')">
                      <i class="bi bi-check-lg me-1"></i>Verify
                    </button>
                  }
                  @if (b.status !== 'REJECTED') {
                    <button class="btn btn-sm btn-outline-danger" (click)="decide(b, 'REJECTED')">Reject</button>
                  }
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="7">
                  <div class="gx-empty">
                    <i class="bi bi-shop"></i>
                    No {{ filter ? filter.toLowerCase() : '' }} businesses.
                  </div>
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    </div>

    @if (previewUrl) {
      <div class="modal fade show" style="display:block; background: rgba(15,23,42,.6)" (click)="previewUrl = null">
        <div class="modal-dialog modal-lg modal-dialog-centered">
          <div class="modal-content">
            <img [src]="previewUrl" style="width:100%; border-radius: 14px" alt="document preview">
          </div>
        </div>
      </div>
    }
  `
})
export class BusinessesComponent implements OnInit {
  private ops = inject(AdminOpsService);

  businesses: AdminBusiness[] = [];
  filter = 'PENDING';
  previewUrl: string | null = null;

  ngOnInit() {
    this.load();
  }

  load() {
    this.ops.getBusinesses(this.filter || undefined).subscribe(res => {
      this.businesses = res;
    });
  }

  decide(b: AdminBusiness, status: 'VERIFIED' | 'REJECTED') {
    this.ops.setBusinessStatus(b.id, status).subscribe(() => this.load());
  }
}
