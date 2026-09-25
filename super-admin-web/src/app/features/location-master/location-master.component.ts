import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';

@Component({
  selector: 'app-location-master',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="gx-page-title">Location master</div>
    <div class="gx-page-sub">
      GeoNames / imported places for hiring and job location search. Not the same as serviceable cities.
      Fuzzy matches still require user confirmation in the app.
    </div>
    @if (error) { <div class="alert alert-danger">{{ error }}</div> }
    <div class="card mb-3">
      <div class="card-body d-flex gap-2 flex-wrap">
        <input class="form-control" style="max-width:320px" placeholder="Search place, district or state"
               [(ngModel)]="q" (keyup.enter)="search()">
        <label class="form-check-label d-flex align-items-center gap-1">
          <input type="checkbox" class="form-check-input" [(ngModel)]="includeInactive"> Include inactive
        </label>
        <button class="btn btn-primary" (click)="search()" [disabled]="loading">Search</button>
      </div>
    </div>
    <div class="table-responsive card">
      <table class="table table-sm mb-0">
        <thead><tr><th>Place</th><th>District</th><th>State</th><th>Source</th><th>Status</th><th></th></tr></thead>
        <tbody>
          @for (row of items; track row.id) {
            <tr>
              <td>{{ row.name }} <code class="small">{{ row.id }}</code></td>
              <td>{{ row.districtName }}</td>
              <td>{{ row.stateName }}</td>
              <td>{{ row.source || '—' }}</td>
              <td>{{ row.isActive ? 'Active' : 'Inactive' }}</td>
              <td class="text-end">
                <button class="btn btn-sm btn-outline-secondary"
                        (click)="toggle(row)">{{ row.isActive ? 'Deactivate' : 'Reactivate' }}</button>
              </td>
            </tr>
          } @empty {
            <tr><td colspan="6" class="text-center text-muted py-4">{{ loading ? 'Loading…' : 'No places' }}</td></tr>
          }
        </tbody>
      </table>
    </div>
    @if (items.length >= limit) {
      <button class="btn btn-link mt-2" (click)="more()">Load more</button>
    }
  `,
})
export class LocationMasterComponent implements OnInit {
  private http = inject(HttpClient);
  q = '';
  includeInactive = true;
  items: any[] = [];
  offset = 0;
  limit = 30;
  loading = false;
  error = '';

  ngOnInit() { this.search(); }

  search() {
    this.offset = 0;
    this.items = [];
    this.fetch();
  }

  more() {
    this.offset += this.limit;
    this.fetch(true);
  }

  fetch(append = false) {
    this.loading = true;
    this.error = '';
    const params: any = { limit: this.limit, offset: this.offset, includeInactive: this.includeInactive };
    if (this.q.trim().length >= 2) params.q = this.q.trim();
    this.http.get<any>('/api/hiring/locations/admin/list', { params }).subscribe({
      next: (res) => {
        const rows = res.items ?? [];
        this.items = append ? [...this.items, ...rows] : rows;
        this.loading = false;
      },
      error: () => {
        this.error = 'Could not load locations. Run hiring catalogue migrations first.';
        this.loading = false;
      },
    });
  }

  toggle(row: any) {
    this.http.patch(`/api/hiring/locations/admin/${row.id}`, { isActive: !row.isActive }).subscribe({
      next: () => this.search(),
      error: () => (this.error = 'Update failed'),
    });
  }
}
