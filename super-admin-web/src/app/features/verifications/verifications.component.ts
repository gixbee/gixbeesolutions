import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdminOpsService, WorkerVerification } from '../../core/services/admin-ops.service';

/// Worker verification queue: pros register via the Earn Hourly wizard and sit
/// at PENDING until approved here. Approve also flips the user's verified
/// flags (trust badge + ranking).
@Component({
  selector: 'app-verifications',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="gx-page-title">Worker Verifications</div>
    <div class="gx-page-sub">Review pro registrations and their uploaded documents.</div>

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
              <th>Pro</th>
              <th>Skills</th>
              <th>Rate</th>
              <th>Languages</th>
              <th>Documents</th>
              <th>Status</th>
              <th class="text-end">Actions</th>
            </tr>
          </thead>
          <tbody>
            @for (w of queue; track w.userId) {
              <tr>
                <td>
                  <div class="fw-bold">{{ w.name || 'Unnamed' }}</div>
                  <div class="text-muted" style="font-size: 12px">{{ w.phone }}</div>
                </td>
                <td style="max-width: 220px">{{ w.skills.join(', ') || '—' }}</td>
                <td>₹{{ w.hourlyRate }}/hr</td>
                <td style="max-width: 160px">{{ w.languages.join(', ') || '—' }}</td>
                <td>
                  @if (w.certificates.length || w.photoUrl) {
                    <div class="d-flex gap-1 flex-wrap">
                      @if (w.photoUrl) {
                        <img class="gx-doc-thumb" [src]="'/api' + w.photoUrl" (click)="preview('/api' + w.photoUrl)" alt="photo">
                      }
                      @for (c of w.certificates; track c) {
                        <img class="gx-doc-thumb" [src]="'/api' + c" (click)="preview('/api' + c)" alt="certificate">
                      }
                    </div>
                  } @else {
                    <span class="text-muted">No documents</span>
                  }
                </td>
                <td>
                  <span class="badge" [ngClass]="{
                    'bg-warning': w.verificationStatus === 'PENDING',
                    'bg-success': w.verificationStatus === 'VERIFIED',
                    'bg-danger': w.verificationStatus === 'REJECTED'
                  }">{{ w.verificationStatus }}</span>
                </td>
                <td class="text-end" style="white-space: nowrap">
                  @if (w.verificationStatus !== 'VERIFIED') {
                    <button class="btn btn-sm btn-primary me-2" (click)="decide(w, 'VERIFIED')">
                      <i class="bi bi-check-lg me-1"></i>Approve
                    </button>
                  }
                  @if (w.verificationStatus !== 'REJECTED') {
                    <button class="btn btn-sm btn-outline-danger" (click)="decide(w, 'REJECTED')">Reject</button>
                  }
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="7">
                  <div class="gx-empty">
                    <i class="bi bi-patch-check"></i>
                    No {{ filter ? filter.toLowerCase() : '' }} verifications.
                  </div>
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    </div>

    <!-- Document preview -->
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
export class VerificationsComponent implements OnInit {
  private ops = inject(AdminOpsService);

  queue: WorkerVerification[] = [];
  filter = 'PENDING';
  previewUrl: string | null = null;

  ngOnInit() {
    this.load();
  }

  load() {
    this.ops.getVerificationQueue(this.filter || undefined).subscribe(res => {
      this.queue = res;
    });
  }

  preview(url: string) {
    this.previewUrl = url;
  }

  decide(w: WorkerVerification, status: 'VERIFIED' | 'REJECTED') {
    this.ops.setWorkerVerification(w.userId, status).subscribe(() => this.load());
  }
}
