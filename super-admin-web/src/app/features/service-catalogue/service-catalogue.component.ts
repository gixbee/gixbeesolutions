import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { HttpClient, HttpParams } from '@angular/common/http';

@Component({
  selector: 'app-service-catalogue',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="gx-page-title">Service catalogue</div>
    <div class="gx-page-sub">Worker trades (PRO_TRADE / PRO_SUB_SKILL), categories and services used by profiles and bookings.</div>
    <div class="d-flex gap-2 mb-3 flex-wrap">
      <select class="form-select" style="max-width:200px" [(ngModel)]="type" (change)="load()">
        <option value="PRO_TRADE">Pro trades</option>
        <option value="PRO_SUB_SKILL">Sub-skills</option>
        <option value="CATEGORY">Categories</option>
        <option value="SERVICE">Services</option>
        <option value="ROLE">Roles</option>
      </select>
      <input class="form-control" style="max-width:240px" placeholder="Search" [(ngModel)]="q" (keyup.enter)="load()">
      <button class="btn btn-outline-primary" (click)="load()">Refresh</button>
    </div>
    @if (error) { <div class="alert alert-danger">{{ error }}</div> }
    <div class="table-responsive card">
      <table class="table table-sm mb-0">
        <thead><tr><th>Label</th><th>Value</th><th>Category</th><th>Status</th></tr></thead>
        <tbody>
          @for (e of items; track e.id) {
            <tr>
              <td>{{ e.icon ? e.icon + ' ' : '' }}{{ e.label }}</td>
              <td><code>{{ e.value }}</code></td>
              <td>{{ e.category || '—' }}</td>
              <td>{{ e.isActive ? 'Active' : 'Inactive' }}</td>
            </tr>
          } @empty {
            <tr><td colspan="4" class="text-muted text-center py-4">No rows — use Master Entries to add trades.</td></tr>
          }
        </tbody>
      </table>
    </div>
    <p class="text-muted small mt-2">Create and edit entries on <a routerLink="/master-entries">Master Entries</a> with matching type filters.</p>
  `,
})
export class ServiceCatalogueComponent implements OnInit {
  private http = inject(HttpClient);
  type = 'PRO_TRADE';
  q = '';
  items: any[] = [];
  error = '';

  ngOnInit() { this.load(); }

  load() {
    let params = new HttpParams().set('type', this.type).set('limit', '100');
    if (this.q.trim()) params = params.set('q', this.q.trim());
    this.http.get<any>('/api/master-entries/admin/list', { params }).subscribe({
      next: (res) => (this.items = res.items ?? []),
      error: () => (this.error = 'Load failed'),
    });
  }
}
