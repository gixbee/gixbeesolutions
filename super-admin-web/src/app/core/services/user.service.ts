import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

export interface ProfessionalSkill {
  id: string;
  name: string;
  hourlyRate: number;
  status: 'PENDING' | 'APPROVED' | 'REJECTED';
  updatedAt: string;
}

export interface TalentProfile {
  id: string;
  skills: string[] | null;
  experience: string | null;
  hourlyRate: number | null;
  currentStatus: string | null;
  preferredRoles: string[] | null;
  preferredLocations: string[] | null;
  jobAlertsEnabled: boolean;
  createdAt: string;
  professionalSkills?: ProfessionalSkill[];
}

export interface User {
  id: string;
  phoneNumber: string;
  name: string | null;
  role: string;
  isVerified: boolean;
  walletBalance: number;
  hasWorkerProfile: boolean;
  approvalStatus: 'PENDING' | 'APPROVED' | 'REJECTED';
  createdAt: string;
  updatedAt: string;
  talentProfile?: TalentProfile;
}

@Injectable({
  providedIn: 'root'
})
export class UserService {
  private http = inject(HttpClient);
  private apiUrl = '/api/admin-user-list';

  getAll(): Observable<User[]> {
    return this.http.get<User[]>(this.apiUrl);
  }

  getSummary(): Observable<any> {
    return this.http.get<any>(`${this.apiUrl}/summary`);
  }

  getById(id: string): Observable<User> {
    return this.http.get<User>(`${this.apiUrl}/${id}`);
  }

  updateVerification(id: string, isVerified: boolean): Observable<User> {
    return this.http.patch<User>(`${this.apiUrl}/${id}/verify`, { isVerified });
  }

  updateApprovalStatus(id: string, status: string): Observable<User> {
    return this.http.patch<User>(`${this.apiUrl}/${id}/status`, { status });
  }

  updateSkillStatus(skillId: string, status: string): Observable<any> {
    return this.http.patch<any>(`${this.apiUrl}/skill/${skillId}/status`, { status });
  }

  update(id: string, data: Partial<User>): Observable<User> {
    return this.http.patch<User>(`${this.apiUrl}/${id}`, data);
  }
}
