import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

export type AdminStaffRole = 'SUPER_ADMIN' | 'OPERATOR';

export interface AdminStaffUser {
  id: string;
  username: string;
  displayName: string;
  staffRole: AdminStaffRole;
  allowedPages: string[];
  isActive: boolean;
  createdAt: string;
}

export interface CreateStaffPayload {
  username: string;
  password: string;
  displayName?: string;
  staffRole: AdminStaffRole;
  allowedPages?: string[];
}

export interface UpdateStaffPayload {
  password?: string;
  displayName?: string;
  staffRole?: AdminStaffRole;
  allowedPages?: string[];
  isActive?: boolean;
}

@Injectable({ providedIn: 'root' })
export class AdminStaffApiService {
  private http = inject(HttpClient);
  private base = '/api/admin-staff';

  listPages(): Observable<{ pages: string[] }> {
    return this.http.get<{ pages: string[] }>(`${this.base}/pages`);
  }

  list(): Observable<AdminStaffUser[]> {
    return this.http.get<AdminStaffUser[]>(this.base);
  }

  create(body: CreateStaffPayload): Observable<AdminStaffUser> {
    return this.http.post<AdminStaffUser>(this.base, body);
  }

  update(id: string, body: UpdateStaffPayload): Observable<AdminStaffUser> {
    return this.http.patch<AdminStaffUser>(`${this.base}/${id}`, body);
  }

  remove(id: string): Observable<{ deleted: true }> {
    return this.http.delete<{ deleted: true }>(`${this.base}/${id}`);
  }
}
