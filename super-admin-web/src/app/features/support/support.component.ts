import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';

interface SupportTicket {
  id: string;
  subject: string;
  message: string;
  status: 'OPEN' | 'RESOLVED';
  reply: string | null;
  createdAt: string;
  resolvedAt: string | null;
  user?: { id: string; name: string; phoneNumber?: string };
}

/// Support inbox: general (non-booking) issues filed from the app's
/// Help & Support screen. Replying resolves the ticket and pushes a
/// notification to the user.
@Component({
  selector: 'app-support',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="gx-page-title">Support Inbox</div>
    <div class="gx-page-sub">Tickets filed by users from Help & Support.</div>

    <div class="card">
      <div class="card-header d-flex justify-content-between align-items-center py-3">
        <select class="form-select" style="width: 180px" [(ngModel)]="filter" (change)="load()">
          <option value="OPEN">Open</option>
          <option value="RESOLVED">Resolved</option>
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
              <th>Filed</th>
              <th>User</th>
              <th>Subject</th>
              <th>Message</th>
              <th>Status</th>
              <th class="text-end">Actions</th>
            </tr>
          </thead>
          <tbody>
            @for (t of tickets; track t.id) {
              <tr>
                <td style="white-space: nowrap">{{ t.createdAt | date:'MMM d, HH:mm' }}</td>
                <td>
                  <div class="fw-bold">{{ t.user?.name || 'Unnamed' }}</div>
                  <div class="text-muted" style="font-size: 12px">{{ t.user?.phoneNumber || '' }}</div>
                </td>
                <td class="fw-semibold" style="max-width: 200px">{{ t.subject }}</td>
                <td style="max-width: 320px">
                  <div>{{ t.message }}</div>
                  @if (t.reply) {
                    <div class="text-muted mt-1" style="font-size: 12px">
                      <i class="bi bi-reply"></i> {{ t.reply }}
                    </div>
                  }
                </td>
                <td>
                  <span class="badge" [ngClass]="t.status === 'RESOLVED' ? 'bg-success' : 'bg-warning'">
                    {{ t.status }}
                  </span>
                </td>
                <td class="text-end">
                  @if (t.status === 'OPEN') {
                    <button class="btn btn-sm btn-primary" (click)="openReply(t)">Reply & resolve</button>
                  }
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="6">
                  <div class="gx-empty">
                    <i class="bi bi-inbox"></i>
                    No {{ filter ? filter.toLowerCase() : '' }} tickets.
                  </div>
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    </div>

    @if (replying) {
      <div class="modal fade show" style="display:block; background: rgba(15,23,42,.6)">
        <div class="modal-dialog modal-dialog-centered">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">Reply to "{{ replying.subject }}"</h5>
              <button type="button" class="btn-close" (click)="replying = null"></button>
            </div>
            <div class="modal-body">
              <p class="text-muted" style="font-size: 13px">{{ replying.message }}</p>
              <label class="form-label">Reply (shown in the user's app + push notification)</label>
              <textarea class="form-control" rows="4" [(ngModel)]="replyText"></textarea>
            </div>
            <div class="modal-footer">
              <button class="btn btn-secondary" (click)="replying = null">Cancel</button>
              <button class="btn btn-primary" [disabled]="!replyText.trim()" (click)="send()">
                Send & resolve
              </button>
            </div>
          </div>
        </div>
      </div>
    }
  `
})
export class SupportComponent implements OnInit {
  private http = inject(HttpClient);

  tickets: SupportTicket[] = [];
  filter = 'OPEN';
  replying: SupportTicket | null = null;
  replyText = '';

  ngOnInit() {
    this.load();
  }

  load() {
    const params: any = { page: '1', limit: '100' };
    if (this.filter) params.status = this.filter;
    this.http.get<SupportTicket[]>('/api/support/admin/all', { params }).subscribe(res => {
      this.tickets = res;
    });
  }

  openReply(t: SupportTicket) {
    this.replying = t;
    this.replyText = '';
  }

  send() {
    if (!this.replying) return;
    this.http
      .patch(`/api/support/admin/${this.replying.id}/resolve`, { reply: this.replyText.trim() })
      .subscribe(() => {
        this.replying = null;
        this.load();
      });
  }
}
