import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';

export interface MasterSetting {
  key: string;
  label: string;
  unit: string;
  description: string;
  min: number;
  max: number;
  fallback: number;
  value: string;
  isActive?: boolean;
  readOnly?: boolean;
  masterEntryId?: string | null;
}

export interface AuditRow {
  id: string;
  section: string;
  entityType: string;
  entityId: string;
  action: string;
  actorUserId: string;
  before?: unknown;
  after?: unknown;
  createdAt: string;
}

@Injectable({ providedIn: 'root' })
export class MasterAdminService {
  private http = inject(HttpClient);
  private base = '/api/master-admin';

  meta(): Observable<{ sections: Array<{ id: string; label: string; permission: string; cacheDomain: string }> }> {
    return this.http.get<any>(`${this.base}/meta`);
  }

  audit(section?: string, limit = 50, offset = 0): Observable<{ items: AuditRow[] }> {
    let params = new HttpParams().set('limit', limit).set('offset', offset);
    if (section) params = params.set('section', section);
    return this.http.get<any>(`${this.base}/audit`, { params });
  }

  pricingSettings(): Observable<{ items: MasterSetting[] }> {
    return this.http.get<any>(`${this.base}/settings/pricing`);
  }

  patchPricing(key: string, value: string, isActive = true) {
    return this.http.patch(`${this.base}/settings/pricing`, { value, isActive }, {
      params: { key },
    });
  }

  operationalSettings(): Observable<{ items: MasterSetting[] }> {
    return this.http.get<any>(`${this.base}/settings/operational`);
  }

  patchOperational(key: string, value: string, isActive = true) {
    return this.http.patch(`${this.base}/settings/operational`, { value, isActive }, {
      params: { key },
    });
  }

  rentalMeta(): Observable<any> {
    return this.http.get(`${this.base}/rental-catalogue-meta`);
  }

  eventMeta(): Observable<any> {
    return this.http.get(`${this.base}/event-catalogue-meta`);
  }
}
