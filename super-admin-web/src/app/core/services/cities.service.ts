import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

export interface City {
  id: string;
  name: string;
  state: string;
  lat: number;
  lng: number;
  isActive: boolean;
  createdAt?: string;
  updatedAt?: string;
}

// Fixed list of Indian states / UTs for the admin form dropdown. States don't
// need their own master — they never change from the admin's point of view.
export const INDIAN_STATES: string[] = [
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
  'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
  'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya',
  'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim',
  'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
  'West Bengal',
  'Andaman and Nicobar Islands', 'Chandigarh',
  'Dadra and Nagar Haveli and Daman and Diu', 'Delhi',
  'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
];

@Injectable({
  providedIn: 'root'
})
export class CitiesService {
  private http = inject(HttpClient);
  private apiUrl = '/api/cities';

  getAll(isActive?: boolean): Observable<City[]> {
    let params: any = {};
    if (isActive !== undefined) params.isActive = isActive;
    return this.http.get<City[]>(this.apiUrl, { params });
  }

  getById(id: string): Observable<City> {
    return this.http.get<City>(`${this.apiUrl}/${id}`);
  }

  create(data: Partial<City>): Observable<City> {
    return this.http.post<City>(this.apiUrl, data);
  }

  update(id: string, data: Partial<City>): Observable<City> {
    return this.http.patch<City>(`${this.apiUrl}/${id}`, data);
  }

  delete(id: string): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`);
  }
}
