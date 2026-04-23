import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

export interface MasterEntry {
  id: string;
  type: string;
  label: string;
  value: string;
  icon?: string;
  category?: string;
  isActive: boolean;
  createdAt?: string;
  updatedAt?: string;
}

@Injectable({
  providedIn: 'root'
})
export class MasterEntriesService {
  private http = inject(HttpClient);
  // We'll configure a proxy in proxy.conf.json to route /api -> http://localhost:3000
  private apiUrl = '/api/master-entries';

  getAll(type?: string, isActive?: boolean): Observable<MasterEntry[]> {
    let params: any = {};
    if (type) params.type = type;
    if (isActive !== undefined) params.isActive = isActive;
    return this.http.get<MasterEntry[]>(this.apiUrl, { params });
  }

  getById(id: string): Observable<MasterEntry> {
    return this.http.get<MasterEntry>(`${this.apiUrl}/${id}`);
  }

  create(data: Partial<MasterEntry>): Observable<MasterEntry> {
    return this.http.post<MasterEntry>(this.apiUrl, data);
  }

  update(id: string, data: Partial<MasterEntry>): Observable<MasterEntry> {
    return this.http.patch<MasterEntry>(`${this.apiUrl}/${id}`, data);
  }

  delete(id: string): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`);
  }

  uploadImage(file: File): Observable<{ url: string; filename: string }> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<{ url: string; filename: string }>('/api/uploads/image', formData);
  }
}
