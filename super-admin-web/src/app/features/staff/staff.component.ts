import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  AdminStaffApiService,
  AdminStaffUser,
  AdminStaffRole,
} from '../../core/services/admin-staff.service';

const PAGE_LABELS: Record<string, string> = {
  dashboard: 'Dashboard',
  bookings: 'Bookings',
  verifications: 'Verifications',
  disputes: 'Disputes',
  support: 'Support',
  businesses: 'Businesses',
  'master-entries': 'Master Entries',
  cities: 'Cities',
  users: 'Users',
  staff: 'Staff (admins)',
};

@Component({
  selector: 'app-staff',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="card shadow-sm border-0 mb-4">
      <div class="card-header bg-white py-3 d-flex justify-content-between align-items-center">
        <div>
          <h4 class="mb-0 fw-bold">Admin staff</h4>
          <small class="text-muted">Create logins and map which portal pages each user can open</small>
        </div>
        <button class="btn btn-primary btn-sm" (click)="openCreate()">
          <i class="bi bi-person-plus me-1"></i> New staff user
        </button>
      </div>
      <div class="card-body p-0">
        <div *ngIf="error" class="alert alert-danger m-3 mb-0">{{ error }}</div>
        <div class="table-responsive">
          <table class="table table-hover align-middle mb-0">
            <thead class="bg-light">
              <tr>
                <th class="px-4 py-3">User</th>
                <th>Role</th>
                <th>Pages</th>
                <th>Status</th>
                <th class="text-end px-4">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr *ngFor="let s of staff">
                <td class="px-4">
                  <div class="fw-semibold">{{ s.displayName || s.username }}</div>
                  <code class="small">{{ s.username }}</code>
                </td>
                <td>
                  <span class="badge rounded-pill"
                    [class.bg-primary]="s.staffRole === 'SUPER_ADMIN'"
                    [class.bg-secondary]="s.staffRole !== 'SUPER_ADMIN'">
                    {{ s.staffRole }}
                  </span>
                </td>
                <td style="max-width: 280px;">
                  <span *ngIf="s.staffRole === 'SUPER_ADMIN'" class="text-muted small">All pages</span>
                  <span *ngIf="s.staffRole !== 'SUPER_ADMIN'" class="small">
                    {{ (s.allowedPages || []).join(', ') || '—' }}
                  </span>
                </td>
                <td>
                  <span class="badge rounded-pill"
                    [class.bg-success-subtle]="s.isActive"
                    [class.text-success]="s.isActive"
                    [class.bg-danger-subtle]="!s.isActive"
                    [class.text-danger]="!s.isActive">
                    {{ s.isActive ? 'Active' : 'Disabled' }}
                  </span>
                </td>
                <td class="text-end px-4">
                  <button class="btn btn-sm btn-light me-1" (click)="openEdit(s)">Edit</button>
                  <button class="btn btn-sm btn-outline-danger" (click)="remove(s)">Delete</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div *ngIf="!loading && staff.length === 0" class="text-center text-muted py-5">
          No staff users yet. Create one to grant role-based portal access.
          <div class="small mt-2">Env ADMIN_USERNAME still works as a bootstrap SuperAdmin.</div>
        </div>
      </div>
    </div>

    <!-- Create / edit modal -->
    <div class="modal fade show d-block" tabindex="-1" *ngIf="showForm"
         style="background: rgba(0,0,0,.4);">
      <div class="modal-dialog modal-lg modal-dialog-centered">
        <div class="modal-content border-0 shadow">
          <div class="modal-header">
            <h5 class="modal-title">{{ editing ? 'Edit staff' : 'New staff user' }}</h5>
            <button type="button" class="btn-close" (click)="closeForm()"></button>
          </div>
          <div class="modal-body">
            <div *ngIf="formError" class="alert alert-danger">{{ formError }}</div>
            <div class="row g-3">
              <div class="col-md-6" *ngIf="!editing">
                <label class="form-label">Username</label>
                <input class="form-control" [(ngModel)]="form.username" autocomplete="off" />
              </div>
              <div class="col-md-6">
                <label class="form-label">Display name</label>
                <input class="form-control" [(ngModel)]="form.displayName" />
              </div>
              <div class="col-md-6">
                <label class="form-label">{{ editing ? 'New password (optional)' : 'Password' }}</label>
                <input type="password" class="form-control" [(ngModel)]="form.password" autocomplete="new-password" />
              </div>
              <div class="col-md-6">
                <label class="form-label">Role</label>
                <select class="form-select" [(ngModel)]="form.staffRole" (ngModelChange)="onRoleChange()">
                  <option value="OPERATOR">OPERATOR — limited pages</option>
                  <option value="SUPER_ADMIN">SUPER_ADMIN — all pages</option>
                </select>
              </div>
              <div class="col-12" *ngIf="form.staffRole === 'OPERATOR'">
                <label class="form-label">Allowed pages</label>
                <div class="row g-2">
                  <div class="col-md-4" *ngFor="let p of assignablePages">
                    <label class="form-check">
                      <input class="form-check-input" type="checkbox"
                        [checked]="form.allowedPages.includes(p)"
                        (change)="togglePage(p, $event)" />
                      <span class="form-check-label">{{ pageLabel(p) }}</span>
                    </label>
                  </div>
                </div>
              </div>
              <div class="col-12" *ngIf="editing">
                <label class="form-check">
                  <input class="form-check-input" type="checkbox" [(ngModel)]="form.isActive" />
                  <span class="form-check-label">Active</span>
                </label>
              </div>
            </div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-light" (click)="closeForm()">Cancel</button>
            <button class="btn btn-primary" [disabled]="saving" (click)="save()">
              {{ saving ? 'Saving…' : 'Save' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  `,
})
export class StaffComponent implements OnInit {
  private api = inject(AdminStaffApiService);

  staff: AdminStaffUser[] = [];
  allPages: string[] = [];
  loading = false;
  error = '';
  showForm = false;
  editing: AdminStaffUser | null = null;
  saving = false;
  formError = '';

  form = {
    username: '',
    password: '',
    displayName: '',
    staffRole: 'OPERATOR' as AdminStaffRole,
    allowedPages: [] as string[],
    isActive: true,
  };

  get assignablePages(): string[] {
    return this.allPages.filter((p) => p !== 'staff');
  }

  ngOnInit() {
    this.reload();
    this.api.listPages().subscribe({
      next: (r) => (this.allPages = r.pages ?? []),
      error: () =>
        (this.allPages = Object.keys(PAGE_LABELS)),
    });
  }

  pageLabel(p: string) {
    return PAGE_LABELS[p] ?? p;
  }

  reload() {
    this.loading = true;
    this.error = '';
    this.api.list().subscribe({
      next: (rows) => {
        this.staff = rows;
        this.loading = false;
      },
      error: (e) => {
        this.loading = false;
        this.error = e?.error?.message || 'Failed to load staff';
      },
    });
  }

  openCreate() {
    this.editing = null;
    this.form = {
      username: '',
      password: '',
      displayName: '',
      staffRole: 'OPERATOR',
      allowedPages: ['dashboard'],
      isActive: true,
    };
    this.formError = '';
    this.showForm = true;
  }

  openEdit(s: AdminStaffUser) {
    this.editing = s;
    this.form = {
      username: s.username,
      password: '',
      displayName: s.displayName || '',
      staffRole: s.staffRole,
      allowedPages: [...(s.allowedPages || [])],
      isActive: s.isActive,
    };
    this.formError = '';
    this.showForm = true;
  }

  closeForm() {
    this.showForm = false;
    this.editing = null;
  }

  onRoleChange() {
    if (this.form.staffRole === 'SUPER_ADMIN') {
      this.form.allowedPages = [];
    } else if (this.form.allowedPages.length === 0) {
      this.form.allowedPages = ['dashboard'];
    }
  }

  togglePage(page: string, ev: Event) {
    const checked = (ev.target as HTMLInputElement).checked;
    if (checked) {
      if (!this.form.allowedPages.includes(page)) {
        this.form.allowedPages = [...this.form.allowedPages, page];
      }
    } else {
      this.form.allowedPages = this.form.allowedPages.filter((p) => p !== page);
    }
  }

  save() {
    this.formError = '';
    this.saving = true;

    if (!this.editing) {
      if (!this.form.username || !this.form.password) {
        this.formError = 'Username and password are required';
        this.saving = false;
        return;
      }
      this.api
        .create({
          username: this.form.username,
          password: this.form.password,
          displayName: this.form.displayName || undefined,
          staffRole: this.form.staffRole,
          allowedPages:
            this.form.staffRole === 'OPERATOR'
              ? this.form.allowedPages
              : undefined,
        })
        .subscribe({
          next: () => {
            this.saving = false;
            this.closeForm();
            this.reload();
          },
          error: (e) => {
            this.saving = false;
            this.formError = e?.error?.message || 'Create failed';
          },
        });
      return;
    }

    const body: any = {
      displayName: this.form.displayName,
      staffRole: this.form.staffRole,
      isActive: this.form.isActive,
      allowedPages:
        this.form.staffRole === 'OPERATOR' ? this.form.allowedPages : undefined,
    };
    if (this.form.password) body.password = this.form.password;

    this.api.update(this.editing.id, body).subscribe({
      next: () => {
        this.saving = false;
        this.closeForm();
        this.reload();
      },
      error: (e) => {
        this.saving = false;
        this.formError = e?.error?.message || 'Update failed';
      },
    });
  }

  remove(s: AdminStaffUser) {
    if (!confirm(`Delete staff user “${s.username}”?`)) return;
    this.api.remove(s.id).subscribe({
      next: () => this.reload(),
      error: (e) => (this.error = e?.error?.message || 'Delete failed'),
    });
  }
}
