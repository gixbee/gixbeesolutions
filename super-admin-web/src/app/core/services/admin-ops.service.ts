import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

// Operational admin endpoints (all AdminGuard'd server-side):
// worker verification queue, dispute review, bookings monitor,
// business moderation.

export interface WorkerVerification {
  userId: string;
  name: string;
  phone: string;
  skills: string[];
  hourlyRate: number;
  bio: string;
  verificationStatus: 'PENDING' | 'VERIFIED' | 'REJECTED';
  languages: string[];
  photoUrl: string | null;
  certificates: string[];
}

export interface AdminBooking {
  id: string;
  skill: string;
  status: string;
  type: string;
  amount: number;
  totalAmount: number | null;
  serviceLocation: string;
  description: string | null;
  paymentMethod: string;
  isPaid: boolean;
  createdAt: string;
  scheduledAt: string | null;
  customer?: { id: string; name: string; phoneNumber?: string };
  operator?: { id: string; name: string; phoneNumber?: string } | null;
  disputeReason?: string | null;
  disputeReporterRole?: string | null;
  disputedAt?: string | null;
  disputeResolution?: string | null;
  disputeResolvedAt?: string | null;
}

export interface AdminBusiness {
  id: string;
  name: string;
  type: string;
  location: string;
  description: string | null;
  documentUrl: string | null;
  hiringProfile?: Record<string, unknown> | null;
  status: 'PENDING' | 'VERIFIED' | 'REJECTED' | 'NEEDS_CHANGES';
  createdAt: string;
  owner?: { id: string; name: string; phoneNumber?: string };
}

// Fair-penalty ledger row (worker_strikes) — see /workers/admin/strikes.
export interface WorkerStrike {
  id: string;
  workerUserId: string;
  bookingId: string | null;
  type: 'GPS_FORFEIT' | 'NO_SHOW' | 'ADMIN';
  reason: string;
  status: 'ACTIVE' | 'APPEALED' | 'OVERTURNED' | 'UPHELD';
  appealMessage: string | null;
  appealedAt: string | null;
  resolutionNote: string | null;
  resolvedAt: string | null;
  createdAt: string;
}

@Injectable({ providedIn: 'root' })
export class AdminOpsService {
  private http = inject(HttpClient);

  // ── Worker verification ──
  getVerificationQueue(status?: string): Observable<WorkerVerification[]> {
    const params: any = {};
    if (status) params.status = status;
    return this.http.get<WorkerVerification[]>('/api/workers/admin/verification-queue', { params });
  }

  setWorkerVerification(userId: string, status: 'VERIFIED' | 'REJECTED'): Observable<any> {
    return this.http.patch(`/api/workers/admin/${userId}/verification`, { status });
  }

  // ── Bookings monitor ──
  getBookings(status?: string, page = 1, limit = 50): Observable<AdminBooking[]> {
    const params: any = { page, limit };
    if (status) params.status = status;
    return this.http.get<AdminBooking[]>('/api/bookings/admin/all', { params });
  }

  // ── Disputes ──
  getDisputes(openOnly: boolean): Observable<AdminBooking[]> {
    return this.http.get<AdminBooking[]>('/api/bookings/admin/disputes', {
      params: { open: openOnly },
    });
  }

  resolveDispute(bookingId: string, resolution: string): Observable<any> {
    return this.http.patch(`/api/bookings/admin/disputes/${bookingId}/resolve`, { resolution });
  }

  // ── Worker strikes / appeals ──
  getStrikes(status?: string): Observable<WorkerStrike[]> {
    const params: any = {};
    if (status) params.status = status;
    return this.http.get<WorkerStrike[]>('/api/workers/admin/strikes', { params });
  }

  resolveStrike(strikeId: string, overturn: boolean, note?: string): Observable<any> {
    return this.http.patch(`/api/workers/admin/strikes/${strikeId}/resolve`, {
      overturn,
      ...(note ? { note } : {}),
    });
  }

  // ── Businesses ──
  getBusinesses(status?: string): Observable<AdminBusiness[]> {
    const params: any = {};
    if (status) params.status = status;
    return this.http.get<AdminBusiness[]>('/api/businesses/admin/all', { params });
  }

  setBusinessStatus(
    id: string,
    status: 'VERIFIED' | 'REJECTED' | 'PENDING' | 'NEEDS_CHANGES',
    reviewNote?: string,
  ): Observable<any> {
    return this.http.patch(`/api/businesses/admin/${id}/status`, {
      status,
      ...(reviewNote ? { reviewNote } : {}),
    });
  }
}
