import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MasterEntriesService, MasterEntry } from '../../core/services/master-entries.service';
import { CitiesService, City } from '../../core/services/cities.service';

@Component({
  selector: 'app-master-entries',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="card shadow-sm">
      <div class="card-header bg-white d-flex justify-content-between align-items-center py-3">
        <h4 class="mb-0">Master Entries</h4>
        <button class="btn btn-primary" (click)="openForm()">
          <i class="bi bi-plus-lg me-1"></i> Add Entry
        </button>
      </div>
      <div class="card-body">
        
        <!-- Filters -->
        <div class="row mb-3 g-2 align-items-center">
          <div class="col-md-3">
            <select class="form-select" [(ngModel)]="filterType" (change)="onFilterChange()">
              <option value="">All Types</option>
              <option value="CATEGORY">Category</option>
              <option value="SERVICE">Service</option>
              <option value="ROLE">Role</option>
              <option value="CONFIGURATION">Configuration</option>
              <option value="BANNER">Home Carousel Banner</option>
              <option value="DEAL">Deal</option>
              <option value="PRO_TRADE">Pro Trade</option>
              <option value="PRO_SUB_SKILL">Pro Sub-Skill</option>
            </select>
          </div>
          <div class="col-md-4">
            <input class="form-control" type="search" placeholder="Search label or value…"
                   [(ngModel)]="search" (input)="page = 1">
          </div>
          <div class="col-md-5 text-md-end text-muted" style="font-size: 13px">
            {{ filtered().length }} entries
          </div>
        </div>

        <!-- Table -->
        <div class="table-responsive">
          <table class="table table-hover align-middle">
            <thead class="table-light">
              <tr>
                <th>Type</th>
                <th>Label</th>
                <th>Value</th>
                <th>Category</th>
                <th>City</th>
                <th>Status</th>
                <th class="text-end">Actions</th>
              </tr>
            </thead>
            <tbody>
              @for (entry of paged(); track entry.id) {
                <tr>
                  <td><span class="badge bg-secondary">{{ entry.type }}</span></td>
                  <td class="fw-bold">{{ entry.icon ? entry.icon + ' ' : '' }}{{ entry.label }}</td>
                  <td>{{ entry.value }}</td>
                  <td>{{ entry.category || '-' }}</td>
                  <td>
                    @if (entry.cityId) {
                      <span class="badge bg-info text-dark">{{ cityName(entry.cityId) }}</span>
                    } @else {
                      <span class="text-muted">Global</span>
                    }
                  </td>
                  <td>
                    <span class="badge" [ngClass]="entry.isActive ? 'bg-success' : 'bg-danger'">
                      {{ entry.isActive ? 'Active' : 'Disabled' }}
                    </span>
                  </td>
                  <td class="text-end">
                    <button class="btn btn-sm btn-outline-primary me-2" (click)="editEntry(entry)">Edit</button>
                    <button class="btn btn-sm" 
                            [ngClass]="entry.isActive ? 'btn-outline-danger' : 'btn-outline-success'"
                            (click)="toggleStatus(entry)">
                      {{ entry.isActive ? 'Disable' : 'Enable' }}
                    </button>
                  </td>
                </tr>
              } @empty {
                <tr>
                  <td colspan="7" class="text-center py-4 text-muted">No master entries found. Create one above!</td>
                </tr>
              }
            </tbody>
          </table>
        </div>

        <!-- Pagination: keeps the page short so the sidebar/topbar stay in view -->
        @if (totalPages() > 1) {
          <div class="d-flex justify-content-between align-items-center pt-3">
            <span class="text-muted" style="font-size: 13px">
              Page {{ page }} of {{ totalPages() }}
            </span>
            <div class="btn-group">
              <button class="btn btn-sm btn-outline-primary" [disabled]="page === 1"
                      (click)="page = page - 1">Previous</button>
              <button class="btn btn-sm btn-outline-primary" [disabled]="page === totalPages()"
                      (click)="page = page + 1">Next</button>
            </div>
          </div>
        }
      </div>
    </div>

    <!-- Side Panel / Modal for Form -->
    @if (showForm) {
      <div class="modal fade show" style="display: block; background: rgba(0,0,0,0.5)">
        <div class="modal-dialog">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">{{ isEditing ? 'Edit Entry' : 'New Master Entry' }}</h5>
              <button type="button" class="btn-close" (click)="closeForm()"></button>
            </div>
            <div class="modal-body">
              <form (ngSubmit)="saveEntry()">
                <div class="mb-3">
                  <label class="form-label">Type</label>
                  <select class="form-select" [(ngModel)]="currentEntry.type" name="type" required>
                    <option value="CATEGORY">Category</option>
                    <option value="SERVICE">Service</option>
                    <option value="ROLE">Role</option>
                    <option value="CONFIGURATION">Configuration</option>
                    <option value="BANNER">Home Carousel Banner</option>
                    <option value="DEAL">Deal</option>
                    <option value="PRO_TRADE">Pro Trade</option>
                    <option value="PRO_SUB_SKILL">Pro Sub-Skill</option>
                  </select>
                </div>
                <div class="mb-3">
                  <label class="form-label">Label (Display Name / Alt Text)</label>
                  <input type="text" class="form-control" [(ngModel)]="currentEntry.label" name="label" required>
                </div>
                
                @if (currentEntry.type === 'BANNER') {
                  <div class="mb-3">
                    <label class="form-label">Banner Image</label>
                    <input type="file" class="form-control" (change)="onFileSelected($event)" accept="image/*">
                    @if (currentEntry.value) {
                      <div class="mt-2">
                        <img [src]="'/api' + currentEntry.value" class="img-thumbnail" style="max-height: 100px">
                      </div>
                    }
                  </div>
                } @else {
                  <div class="mb-3">
                    <label class="form-label">
                      {{ currentEntry.type === 'PRO_TRADE' ? 'Sub-skills (Comma-separated)' : 'Value (Internal Key / Config)' }}
                    </label>
                    <input type="text" class="form-control" [(ngModel)]="currentEntry.value" name="value" required>
                  </div>
                }
                
                @if (currentEntry.type !== 'BANNER') {
                  <div class="mb-3">
                    <label class="form-label">Icon (Optional — emoji or icon name)</label>
                    <input type="text" class="form-control" [(ngModel)]="currentEntry.icon" name="icon" placeholder="e.g. 🧹 or bi-wrench">
                  </div>
                }
                <div class="mb-3">
                  <label class="form-label">Target URL / Category (Optional)</label>
                  <input type="text" class="form-control" [(ngModel)]="currentEntry.category" name="category" placeholder="e.g. /offers/summer">
                </div>
                <div class="mb-3">
                  <label class="form-label">City Scope</label>
                  <select class="form-select" [(ngModel)]="currentEntry.cityId" name="cityId">
                    <option [ngValue]="null">All cities (Global)</option>
                    @for (c of cities; track c.id) {
                      <option [ngValue]="c.id">{{ c.name }}, {{ c.state }}</option>
                    }
                  </select>
                  <div class="form-text">Scoped entries are shown only to users in that city (banners, deals).</div>
                </div>
                <div class="form-check form-switch mb-3">
                  <input class="form-check-input" type="checkbox" [(ngModel)]="currentEntry.isActive" name="isActive" id="isActiveCheck">
                  <label class="form-check-label" for="isActiveCheck">Is Active</label>
                </div>
                <div class="text-end">
                  <button type="button" class="btn btn-secondary me-2" (click)="closeForm()">Cancel</button>
                  <button type="submit" class="btn btn-primary">Save Entry</button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    }
  `
})
export class MasterEntriesComponent implements OnInit {
  private service = inject(MasterEntriesService);
  private citiesService = inject(CitiesService);

  entries: MasterEntry[] = [];
  cities: City[] = [];
  filterType: string = '';
  search = '';
  page = 1;
  readonly pageSize = 15;

  /// Type filter is applied server-side; search is client-side over the result.
  filtered(): MasterEntry[] {
    const q = this.search.trim().toLowerCase();
    if (!q) return this.entries;
    return this.entries.filter(
      (e) =>
        e.label?.toLowerCase().includes(q) ||
        e.value?.toLowerCase().includes(q) ||
        e.category?.toLowerCase().includes(q),
    );
  }

  totalPages(): number {
    return Math.max(1, Math.ceil(this.filtered().length / this.pageSize));
  }

  paged(): MasterEntry[] {
    const list = this.filtered();
    if (this.page > this.totalPages()) this.page = 1;
    const start = (this.page - 1) * this.pageSize;
    return list.slice(start, start + this.pageSize);
  }

  onFilterChange() {
    this.page = 1;
    this.loadEntries();
  }

  showForm = false;
  isEditing = false;
  currentEntry: Partial<MasterEntry> = {};
  uploading = false;

  ngOnInit() {
    this.loadEntries();
    // City list for the scope dropdown + name lookup in the table.
    this.citiesService.getAll().subscribe(res => {
      this.cities = res;
    });
  }

  cityName(id: string): string {
    const c = this.cities.find(x => x.id === id);
    return c ? c.name : '…';
  }

  loadEntries() {
    this.service.getAll(this.filterType || undefined).subscribe(res => {
      this.entries = res;
    });
  }

  openForm() {
    this.isEditing = false;
    this.currentEntry = { type: 'CATEGORY', isActive: true, cityId: null };
    this.showForm = true;
  }

  editEntry(entry: MasterEntry) {
    this.isEditing = true;
    // Normalise undefined → null so the "All cities (Global)" [ngValue]="null"
    // option is pre-selected for unscoped entries.
    this.currentEntry = { ...entry, cityId: entry.cityId ?? null };
    this.showForm = true;
  }

  closeForm() {
    this.showForm = false;
    this.currentEntry = {};
  }

  saveEntry() {
    if (this.isEditing && this.currentEntry.id) {
      this.service.update(this.currentEntry.id, this.currentEntry).subscribe(() => {
        this.loadEntries();
        this.closeForm();
      });
    } else {
      this.service.create(this.currentEntry).subscribe(() => {
        this.loadEntries();
        this.closeForm();
      });
    }
  }

  toggleStatus(entry: MasterEntry) {
    this.service.update(entry.id, { isActive: !entry.isActive }).subscribe(() => {
      this.loadEntries();
    });
  }

  onFileSelected(event: any) {
    const file: File = event.target.files[0];
    if (file) {
      this.uploading = true;
      this.service.uploadImage(file).subscribe({
        next: (res) => {
          this.currentEntry.value = res.url;
          this.uploading = false;
        },
        error: (err) => {
          console.error('Upload failed', err);
          this.uploading = false;
          alert('Image upload failed. Please try again.');
        }
      });
    }
  }
}
