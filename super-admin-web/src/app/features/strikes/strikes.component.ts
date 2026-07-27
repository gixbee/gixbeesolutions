import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdminOpsService, WorkerStrike } from '../../core/services/admin-ops.service';

/// Strike appeals review: every strike a pro receives carries a written
/// reason and can be appealed once. This queue shows appeals awaiting a
/// human decision (default) or the full ledger. Overturning removes the
/// strike from the pro's count — dropping them under the suspension
/// threshold unblocks Go Live immediately; upholding keeps it. Either way
/// the pro is notified with the note written here, so write it FOR THEM.
@Component({
  selector: 'app-strikes',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="gx-page-title">Strike Appeals</div>
    <div class="gx-page-sub">
      Pros appeal job-violation strikes here. 3 counting strikes = suspended from going live.
    </div>

    <div class="card">
      <div class="card-header d-flex justify-content-between align-items-center py-3">
        <div class="btn-group btn-group-sm" role="group">
          <button class="btn"
                  [ngClass]="filter === 'APPEALED' ? 'btn-primary' : 'btn-outline-primary'"
                  (click)="setFilter('APPEALED')">
            Awaiting review
          </button>
          <button class="btn"
                  [ngClass]="filter === '' ? 'btn-primary' : 'btn-outline-primary'"
                  (click)="setFilter('')">
            All strikes
          </button>
        </div>
        <button class="btn btn-sm btn-outline-primary" (click)="load()">
          <i class="bi bi-arrow-clockwise me-1"></i>Refresh
        </button>
      </div>
      <div class="table-responsive">
        <table class="table table-hover align-middle">
          <thead>
            <tr>
              <th>Issued</th>
              <th>Type</th>
              <th>Reason given to the pro</th>
              <th>Pro's appeal</th>
              <th>Status</th>
              <th class="text-end">Actions</th>
            </tr>
          </thead>
          <tbody>
            @for (s of strikes; track s.id) {
              <tr>
                <td style="white-space: nowrap">
                  <div>{{ s.createdAt | date:'MMM d, HH:mm' }}</div>
                  @if (s.bookingId) {
                    <div class="text-muted" style="font-size: 11px">bk {{ s.bookingId.slice(0, 8) }}…</div>
                  }
                </td>
                <td>
                  <span class="badge"
                        [ngClass]="{
                          'bg-warning text-dark': s.type === 'GPS_FORFEIT',
                          'bg-danger': s.type === 'NO_SHOW',
                          'bg-secondary': s.type === 'ADMIN'
                        }">
                    {{ typeLabels[s.type] || s.type }}
                  </span>
                </td>
                <td style="max-width: 260px; font-size: 13px">{{ s.reason }}</td>
                <td style="max-width: 280px; font-size: 13px">
                  @if (s.appealMessage) {
                    <div>"{{ s.appealMessage }}"</div>
                    <div class="text-muted" style="font-size: 11px">{{ s.appealedAt | date:'MMM d, HH:mm' }}</div>
                  } @else {
                    <span class="text-muted">Not appealed</span>
                  }
                </td>
                <td>
                  <span class="badge"
                        [ngClass]="{
                          'bg-warning text-dark': s.status === 'ACTIVE',
                          'bg-info': s.status === 'APPEALED',
                          'bg-success': s.status === 'OVERTURNED',
                          'bg-danger': s.status === 'UPHELD'
                        }">
                    {{ s.status }}
                  </span>
                </td>
                <td class="text-end">
                  @if (s.status === 'ACTIVE' || s.status === 'APPEALED') {
                    <button class="btn btn-sm btn-primary" (click)="openReview(s)">Review</button>
                  } @else {
                    <span class="text-muted" style="font-size: 12px">{{ s.resolutionNote || '—' }}</span>
                  }
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="6">
                  <div class="gx-empty">
                    <i class="bi bi-shield-check"></i>
                    {{ filter === 'APPEALED' ? 'No appeals waiting — inbox zero.' : 'No strikes recorded.' }}
                  </div>
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    </div>

    <!-- Review modal -->
    @if (reviewing) {
      <div class="modal fade show" style="display:block; background: rgba(15,23,42,.6)">
        <div class="modal-dialog modal-dialog-centered">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">Review strike</h5>
              <button type="button" class="btn-close" (click)="reviewing = null"></button>
            </div>
            <div class="modal-body">
              <p style="font-size: 13px"><strong>Strike:</strong> {{ reviewing.reason }}</p>
              @if (reviewing.appealMessage) {
                <p class="text-muted" style="font-size: 13px">
                  <strong>Pro's appeal:</strong> "{{ reviewing.appealMessage }}"
                </p>
              } @else {
                <p class="text-muted" style="font-size: 13px">The pro has not appealed this strike.</p>
              }
              <label class="form-label">Note to the pro (sent with the outcome)</label>
              <textarea class="form-control" rows="3" [(ngModel)]="reviewNote"
                        placeholder="e.g. Verified the GPS outage in system logs — strike removed."></textarea>
            </div>
            <div class="modal-footer">
              <button class="btn btn-secondary" (click)="reviewing = null">Cancel</button>
              <button class="btn btn-outline-danger" (click)="resolve(false)">
                <i class="bi bi-hand-thumbs-down me-1"></i>Uphold strike
              </button>
              <button class="btn btn-success" (click)="resolve(true)">
                <i class="bi bi-hand-thumbs-up me-1"></i>Overturn (remove)
              </button>
            </div>
          </div>
        </div>
      </div>
    }
  `
})
export class StrikesComponent implements OnInit {
  private ops = inject(AdminOpsService);

  strikes: WorkerStrike[] = [];
  filter = 'APPEALED';
  reviewing: WorkerStrike | null = null;
  reviewNote = '';

  readonly typeLabels: Record<string, string> = {
    GPS_FORFEIT: 'GPS forfeit',
    NO_SHOW: 'No-show',
    ADMIN: 'Policy',
  };

  ngOnInit() {
    this.load();
  }

  setFilter(f: string) {
    this.filter = f;
    this.load();
  }

  load() {
    this.ops.getStrikes(this.filter || undefined).subscribe(res => {
      this.strikes = res;
    });
  }

  openReview(s: WorkerStrike) {
    this.reviewing = s;
    this.reviewNote = '';
  }

  resolve(overturn: boolean) {
    if (!this.reviewing) return;
    this.ops
      .resolveStrike(this.reviewing.id, overturn, this.reviewNote.trim() || undefined)
      .subscribe(() => {
        this.reviewing = null;
        this.load();
      });
  }
}
