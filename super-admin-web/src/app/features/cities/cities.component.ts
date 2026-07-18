import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CitiesService, City, INDIAN_STATES } from '../../core/services/cities.service';

// Serviceable-cities master. The consumer app's home location picker lists
// ACTIVE cities from GET /cities, and banners/deals/businesses can be scoped
// to a city — so launching a new city is just "Add City" here, no app release.
// lat/lng are the city-centre coordinates (used by the app to auto-detect the
// nearest active city from GPS); grab them from Google Maps (right-click →
// copy coordinates).
@Component({
  selector: 'app-cities',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="card shadow-sm">
      <div class="card-header bg-white d-flex justify-content-between align-items-center py-3">
        <h4 class="mb-0">Serviceable Cities</h4>
        <button class="btn btn-primary" (click)="openForm()">
          <i class="bi bi-plus-lg me-1"></i> Add City
        </button>
      </div>
      <div class="card-body">

        <p class="text-muted small">
          Active cities appear in the mobile app's location picker. Banners, deals and
          businesses can be scoped to a city — users in other cities won't see them.
        </p>

        <!-- Table -->
        <div class="table-responsive">
          <table class="table table-hover align-middle">
            <thead class="table-light">
              <tr>
                <th>City</th>
                <th>State</th>
                <th>Coordinates</th>
                <th>Status</th>
                <th class="text-end">Actions</th>
              </tr>
            </thead>
            <tbody>
              @for (city of cities; track city.id) {
                <tr>
                  <td class="fw-bold">{{ city.name }}</td>
                  <td>{{ city.state }}</td>
                  <td class="text-muted small">{{ city.lat }}, {{ city.lng }}</td>
                  <td>
                    <span class="badge" [ngClass]="city.isActive ? 'bg-success' : 'bg-danger'">
                      {{ city.isActive ? 'Active' : 'Disabled' }}
                    </span>
                  </td>
                  <td class="text-end">
                    <button class="btn btn-sm btn-outline-primary me-2" (click)="editCity(city)">Edit</button>
                    <button class="btn btn-sm"
                            [ngClass]="city.isActive ? 'btn-outline-danger' : 'btn-outline-success'"
                            (click)="toggleStatus(city)">
                      {{ city.isActive ? 'Disable' : 'Enable' }}
                    </button>
                  </td>
                </tr>
              } @empty {
                <tr>
                  <td colspan="5" class="text-center py-4 text-muted">No cities yet. Add your first launch city!</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- Modal Form -->
    @if (showForm) {
      <div class="modal fade show" style="display: block; background: rgba(0,0,0,0.5)">
        <div class="modal-dialog">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">{{ isEditing ? 'Edit City' : 'New City' }}</h5>
              <button type="button" class="btn-close" (click)="closeForm()"></button>
            </div>
            <div class="modal-body">
              <form (ngSubmit)="saveCity()">
                <div class="mb-3">
                  <label class="form-label">State</label>
                  <select class="form-select" [(ngModel)]="currentCity.state" name="state" required>
                    <option value="" disabled selected>Select state…</option>
                    @for (s of states; track s) {
                      <option [value]="s">{{ s }}</option>
                    }
                  </select>
                </div>
                <div class="mb-3">
                  <label class="form-label">City Name</label>
                  <input type="text" class="form-control" [(ngModel)]="currentCity.name" name="name" required>
                </div>
                <div class="row">
                  <div class="col-6 mb-3">
                    <label class="form-label">Latitude</label>
                    <input type="number" step="any" class="form-control" [(ngModel)]="currentCity.lat" name="lat" required placeholder="e.g. 11.0168">
                  </div>
                  <div class="col-6 mb-3">
                    <label class="form-label">Longitude</label>
                    <input type="number" step="any" class="form-control" [(ngModel)]="currentCity.lng" name="lng" required placeholder="e.g. 76.9558">
                  </div>
                </div>
                <div class="form-text mb-3">
                  City-centre coordinates. In Google Maps: right-click the city centre → the first menu row copies "lat, lng".
                </div>
                <div class="form-check form-switch mb-3">
                  <input class="form-check-input" type="checkbox" [(ngModel)]="currentCity.isActive" name="isActive" id="cityActiveCheck">
                  <label class="form-check-label" for="cityActiveCheck">Is Active (visible in the app)</label>
                </div>
                <div class="text-end">
                  <button type="button" class="btn btn-secondary me-2" (click)="closeForm()">Cancel</button>
                  <button type="submit" class="btn btn-primary">Save City</button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    }
  `
})
export class CitiesComponent implements OnInit {
  private service = inject(CitiesService);

  cities: City[] = [];
  states = INDIAN_STATES;

  showForm = false;
  isEditing = false;
  currentCity: Partial<City> = {};

  ngOnInit() {
    this.loadCities();
  }

  loadCities() {
    this.service.getAll().subscribe(res => {
      this.cities = res;
    });
  }

  openForm() {
    this.isEditing = false;
    this.currentCity = { state: '', isActive: true };
    this.showForm = true;
  }

  editCity(city: City) {
    this.isEditing = true;
    this.currentCity = { ...city };
    this.showForm = true;
  }

  closeForm() {
    this.showForm = false;
    this.currentCity = {};
  }

  saveCity() {
    // Coerce number inputs (ngModel on type=number gives numbers, but guard
    // against string values from edge cases so the API's IsNumber passes).
    const payload: Partial<City> = {
      name: this.currentCity.name,
      state: this.currentCity.state,
      lat: this.currentCity.lat !== undefined ? Number(this.currentCity.lat) : undefined,
      lng: this.currentCity.lng !== undefined ? Number(this.currentCity.lng) : undefined,
      isActive: this.currentCity.isActive,
    };
    if (this.isEditing && this.currentCity.id) {
      this.service.update(this.currentCity.id, payload).subscribe(() => {
        this.loadCities();
        this.closeForm();
      });
    } else {
      this.service.create(payload).subscribe(() => {
        this.loadCities();
        this.closeForm();
      });
    }
  }

  toggleStatus(city: City) {
    this.service.update(city.id, { isActive: !city.isActive }).subscribe(() => {
      this.loadCities();
    });
  }
}
