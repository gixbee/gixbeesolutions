import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-hiring-catalogue',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="gx-page-title">Hiring catalogue</div>
    <div class="gx-page-sub">Manage sectors, positions, specializations, skills, qualifications and aliases. Serviceable cities stay separate.</div>
    <div *ngIf="error" class="alert alert-danger">{{ error }}</div>
    <div class="card mb-3">
      <div class="card-header d-flex justify-content-between">
        <span>Import</span>
        <button class="btn btn-sm btn-primary" (click)="importBundled()" [disabled]="busy">Import bundled catalogue</button>
      </div>
      <div class="card-body" *ngIf="message"><p>{{ message }}</p></div>
    </div>

    <div class="card mb-3">
      <div class="card-header">Sectors</div>
      <div class="card-body">
        <table class="table">
          <tbody>
            <tr *ngFor="let sector of sectors">
              <td>{{ sector.label }} <span class="text-muted">{{ sector.id }}</span></td>
              <td class="text-end">
                <button class="btn btn-sm btn-outline-secondary" (click)="setActive('sectors', sector.id, !sector.isActive)">
                  {{ sector.isActive ? 'Deactivate' : 'Reactivate' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <div class="d-flex gap-2">
          <input class="form-control" placeholder="id" [(ngModel)]="sectorId">
          <input class="form-control" placeholder="label" [(ngModel)]="sectorLabel">
          <button class="btn btn-outline-primary" (click)="addSector()">Add</button>
        </div>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-header">Positions</div>
      <div class="card-body">
        <div class="d-flex gap-2 mb-2">
          <input class="form-control" placeholder="Search position" [(ngModel)]="positionQuery" (ngModelChange)="searchPositions()">
        </div>
        <table class="table">
          <tbody>
            <tr *ngFor="let position of positions">
              <td>
                <button class="btn btn-link p-0" (click)="openPosition(position.id)">{{ position.label }}</button>
                <span class="text-muted"> {{ position.id }}</span>
              </td>
              <td class="text-end">
                <button class="btn btn-sm btn-outline-secondary" (click)="setActive('positions', position.id, !position.isActive)">
                  {{ position.isActive ? 'Deactivate' : 'Reactivate' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <div class="d-flex gap-2">
          <input class="form-control" placeholder="position id" [(ngModel)]="newPositionId">
          <input class="form-control" placeholder="label" [(ngModel)]="newPositionLabel">
          <input class="form-control" placeholder="sector id" [(ngModel)]="newPositionSector">
          <button class="btn btn-outline-primary" (click)="addPosition()">Add</button>
        </div>
      </div>
    </div>

    <div class="card mb-3" *ngIf="detail">
      <div class="card-header">{{ detail.label }}</div>
      <div class="card-body">
        <h4>Specializations</h4>
        <div *ngFor="let spec of detail.specializations" class="d-flex justify-content-between mb-1">
          <span>{{ spec.label }} <span class="text-muted">{{ spec.id }}</span></span>
          <button class="btn btn-sm btn-outline-secondary" (click)="patch('/api/hiring/catalogue/admin/specializations/' + spec.id, { isActive: !spec.isActive })">
            {{ spec.isActive ? 'Deactivate' : 'Reactivate' }}
          </button>
        </div>
        <div class="d-flex gap-2 mb-3">
          <input class="form-control" placeholder="specialization id" [(ngModel)]="specId">
          <input class="form-control" placeholder="label" [(ngModel)]="specLabel">
          <button class="btn btn-outline-primary" (click)="addSpec()">Add</button>
        </div>
        <h4>Skills</h4>
        <div *ngFor="let skill of detail.skills" class="d-flex justify-content-between mb-1">
          <span>{{ skill.label }} <span class="text-muted">{{ skill.tier }}</span></span>
          <button class="btn btn-sm btn-outline-secondary" (click)="patch('/api/hiring/catalogue/admin/skills/' + skill.id, { isActive: !skill.isActive })">
            {{ skill.isActive ? 'Deactivate' : 'Reactivate' }}
          </button>
        </div>
        <div class="d-flex gap-2 mb-3">
          <input class="form-control" placeholder="skill id" [(ngModel)]="skillId">
          <input class="form-control" placeholder="label" [(ngModel)]="skillLabel">
          <select class="form-select" [(ngModel)]="skillTier"><option>suggested</option><option>more</option></select>
          <button class="btn btn-outline-primary" (click)="addSkill()">Add and link</button>
        </div>
        <h4>Alias</h4>
        <div class="d-flex gap-2">
          <input class="form-control" placeholder="alternate name" [(ngModel)]="alias">
          <button class="btn btn-outline-primary" (click)="addAlias()">Add position alias</button>
        </div>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-header">Qualifications</div>
      <div class="card-body">
        <div *ngFor="let qual of qualifications" class="d-flex justify-content-between mb-1">
          <span>{{ qual.label }}</span>
          <button class="btn btn-sm btn-outline-secondary" (click)="patch('/api/hiring/catalogue/admin/qualifications/' + qual.id, { isActive: !qual.isActive })">
            {{ qual.isActive ? 'Deactivate' : 'Reactivate' }}
          </button>
        </div>
        <div class="d-flex gap-2">
          <input class="form-control" placeholder="id" [(ngModel)]="qualId">
          <input class="form-control" placeholder="label" [(ngModel)]="qualLabel">
          <button class="btn btn-outline-primary" (click)="addQualification()">Add</button>
        </div>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-header">Languages</div>
      <div class="card-body">
        <div *ngFor="let lang of languages" class="d-flex justify-content-between mb-1">
          <span>{{ lang.label }} <span class="text-muted">{{ lang.id }}</span></span>
          <button class="btn btn-sm btn-outline-secondary" (click)="patch('/api/hiring/catalogue/admin/languages/' + lang.id, { isActive: !lang.isActive })">
            {{ lang.isActive ? 'Deactivate' : 'Reactivate' }}
          </button>
        </div>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-header">Employment types</div>
      <div class="card-body">
        <div *ngFor="let emp of employmentTypes" class="d-flex justify-content-between mb-1">
          <span>{{ emp.label }} <code>{{ emp.code }}</code></span>
          <button class="btn btn-sm btn-outline-secondary" (click)="patch('/api/hiring/catalogue/admin/employment-types/' + emp.code, { isActive: !emp.isActive })">
            {{ emp.isActive ? 'Deactivate' : 'Reactivate' }}
          </button>
        </div>
      </div>
    </div>

    <div class="card">
      <div class="card-body">
        <p class="mb-0">Geographic places are managed on <a routerLink="/location-master">Location master</a>.
        Legacy ID map: <button class="btn btn-link p-0" (click)="loadLegacy()">view JSON</button></p>
        <pre *ngIf="legacyMap" class="small mt-2 bg-light p-2">{{ legacyMap | json }}</pre>
      </div>
    </div>
  `,
})
export class HiringCatalogueComponent implements OnInit {
  private http = inject(HttpClient);
  sectors: any[] = [];
  positions: any[] = [];
  qualifications: any[] = [];
  languages: any[] = [];
  employmentTypes: any[] = [];
  legacyMap: any = null;
  error = '';
  detail: any = null;
  message = '';
  busy = false;
  sectorId = '';
  sectorLabel = '';
  positionQuery = '';
  newPositionId = '';
  newPositionLabel = '';
  newPositionSector = '';
  specId = '';
  specLabel = '';
  skillId = '';
  skillLabel = '';
  skillTier = 'suggested';
  alias = '';
  qualId = '';
  qualLabel = '';
  ngOnInit() { this.load(); this.searchPositions(); }

  load() {
    this.http.get<any>('/api/hiring/catalogue', { params: { includeInactive: 'true' } }).subscribe({
      next: (res) => {
        this.sectors = res.sectors ?? [];
        this.qualifications = res.qualifications ?? [];
        this.languages = res.languages ?? [];
        this.employmentTypes = res.employmentTypes ?? [];
      },
      error: () => (this.error = 'Failed to load catalogue snapshot'),
    });
  }

  loadLegacy() {
    this.http.get<any>('/api/hiring/catalogue/admin/legacy-map').subscribe((m) => (this.legacyMap = m));
  }

  importBundled() {
    this.busy = true;
    this.http.post<any>('/api/hiring/catalogue/admin/import', {}).subscribe({
      next: (res) => {
        this.message = `Imported ${res.positions} positions in ${res.sectors} sectors.`;
        this.busy = false;
        this.load();
      },
      error: () => {
        this.message = 'Import failed. Run the hiring catalogue migration first.';
        this.busy = false;
      },
    });
  }

  addSector() {
    this.http.post('/api/hiring/catalogue/admin/sectors', { id: this.sectorId, label: this.sectorLabel }).subscribe(() => {
      this.sectorId = '';
      this.sectorLabel = '';
      this.load();
    });
  }

  setActive(kind: 'sectors' | 'positions', id: string, isActive: boolean) {
    this.patch(`/api/hiring/catalogue/admin/${kind}/${id}`, { isActive });
  }

  searchPositions() {
    this.http.get<any>('/api/hiring/catalogue/positions', {
      params: { q: this.positionQuery, includeInactive: 'true', limit: 30 },
    }).subscribe((res) => this.positions = res.items ?? []);
  }

  addPosition() {
    this.http.post('/api/hiring/catalogue/admin/positions', {
      id: this.newPositionId,
      label: this.newPositionLabel,
      sectorId: this.newPositionSector,
    }).subscribe(() => {
      this.newPositionId = '';
      this.newPositionLabel = '';
      this.searchPositions();
    });
  }

  openPosition(id: string) {
    this.http.get<any>(`/api/hiring/catalogue/positions/${id}`).subscribe((res) => this.detail = res);
  }

  addSpec() {
    if (!this.detail) return;
    this.http.post('/api/hiring/catalogue/admin/specializations', {
      id: this.specId, positionId: this.detail.id, label: this.specLabel,
    }).subscribe(() => { this.specId = ''; this.specLabel = ''; this.openPosition(this.detail.id); });
  }

  addSkill() {
    if (!this.detail) return;
    this.http.post('/api/hiring/catalogue/admin/skills', { id: this.skillId, label: this.skillLabel }).subscribe(() => {
      this.http.post('/api/hiring/catalogue/admin/position-skills', {
        positionId: this.detail.id, skillId: this.skillId, tier: this.skillTier,
      }).subscribe(() => { this.skillId = ''; this.skillLabel = ''; this.openPosition(this.detail.id); });
    });
  }

  addAlias() {
    if (!this.detail || !this.alias) return;
    this.http.post('/api/hiring/catalogue/admin/aliases', {
      entityType: 'position', entityId: this.detail.id, alias: this.alias,
    }).subscribe(() => this.alias = '');
  }

  addQualification() {
    this.http.post('/api/hiring/catalogue/admin/qualifications', { id: this.qualId, label: this.qualLabel }).subscribe(() => {
      this.qualId = '';
      this.qualLabel = '';
      this.load();
    });
  }

  patch(url: string, body: object) {
    this.http.patch(url, body).subscribe(() => {
      this.load();
      this.searchPositions();
      if (this.detail) this.openPosition(this.detail.id);
    });
  }
}
