import { Component, Input, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MasterAdminService, MasterSetting } from '../../core/services/master-admin.service';

@Component({
  selector: 'app-settings-panel',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="gx-page-title">{{ title }}</div>
    <div class="gx-page-sub">{{ subtitle }}</div>
    @if (message) { <div class="alert alert-info">{{ message }}</div> }
    @if (error) { <div class="alert alert-danger">{{ error }}</div> }
    <div class="card">
      <div class="table-responsive">
        <table class="table mb-0">
          <thead><tr><th>Setting</th><th>Value</th><th>Unit</th><th></th></tr></thead>
          <tbody>
            @for (s of items; track s.key) {
              <tr>
                <td>
                  <div class="fw-semibold">{{ s.label }}</div>
                  <div class="text-muted small">{{ s.description }}</div>
                  @if (s.readOnly) { <span class="badge bg-secondary">Read-only</span> }
                </td>
                <td style="max-width:120px">
                  @if (!s.readOnly) {
                    <input class="form-control form-control-sm" [(ngModel)]="draft[s.key]" />
                  } @else {
                    {{ s.value }}
                  }
                </td>
                <td>{{ s.unit }}</td>
                <td class="text-end">
                  @if (!s.readOnly) {
                    <button class="btn btn-sm btn-primary" (click)="save(s)" [disabled]="busy">Save</button>
                  }
                </td>
              </tr>
            } @empty {
              <tr><td colspan="4" class="text-center py-4 text-muted">No settings</td></tr>
            }
          </tbody>
        </table>
      </div>
    </div>
  `,
})
export class SettingsPanelComponent implements OnInit {
  @Input({ required: true }) mode!: 'pricing' | 'operational';
  @Input({ required: true }) title!: string;
  @Input({ required: true }) subtitle!: string;

  private api = inject(MasterAdminService);
  items: MasterSetting[] = [];
  draft: Record<string, string> = {};
  message = '';
  error = '';
  busy = false;

  ngOnInit() { this.load(); }

  load() {
    const obs = this.mode === 'pricing' ? this.api.pricingSettings() : this.api.operationalSettings();
    obs.subscribe({
      next: (res) => {
        this.items = res.items ?? [];
        for (const s of this.items) {
          if (!s.readOnly) this.draft[s.key] = s.value;
        }
      },
      error: () => (this.error = 'Failed to load settings'),
    });
  }

  save(s: MasterSetting) {
    const value = (this.draft[s.key] ?? '').trim();
    const n = Number(value);
    if (!Number.isFinite(n) || n < s.min || n > s.max) {
      this.error = `${s.label} must be between ${s.min} and ${s.max}`;
      return;
    }
    this.busy = true;
    this.error = '';
    const call =
      this.mode === 'pricing'
        ? this.api.patchPricing(s.key, value)
        : this.api.patchOperational(s.key, value);
    call.subscribe({
      next: () => {
        this.message = `Saved ${s.label}`;
        this.busy = false;
        this.load();
      },
      error: (e) => {
        this.error = e?.error?.message || 'Save failed';
        this.busy = false;
      },
    });
  }
}
