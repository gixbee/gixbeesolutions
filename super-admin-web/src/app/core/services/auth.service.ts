import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { BehaviorSubject, Observable, tap } from 'rxjs';

export type AdminStaffRole = 'SUPER_ADMIN' | 'OPERATOR';

export interface AdminSession {
  accessToken: string;
  staffRole: AdminStaffRole;
  pages: string[];
  displayName: string;
  username: string;
}

const TOKEN_KEY = 'gixbee_admin_token';
const SESSION_KEY = 'gixbee_admin_session';

@Injectable({
  providedIn: 'root',
})
export class AuthService {
  private http = inject(HttpClient);
  private router = inject(Router);

  private isLoggedInSubject = new BehaviorSubject<boolean>(this.hasToken());
  public isLoggedIn$ = this.isLoggedInSubject.asObservable();

  private sessionSubject = new BehaviorSubject<AdminSession | null>(
    this.readSession(),
  );
  public session$ = this.sessionSubject.asObservable();

  login(username: string, password: string): Observable<AdminSession> {
    return this.http
      .post<AdminSession>('/api/auth/admin-login', { username, password })
      .pipe(
        tap((res) => {
          if (res.accessToken) {
            localStorage.setItem(TOKEN_KEY, res.accessToken);
            const session: AdminSession = {
              accessToken: res.accessToken,
              staffRole: res.staffRole ?? 'SUPER_ADMIN',
              pages: res.pages ?? [],
              displayName: res.displayName ?? username,
              username: res.username ?? username,
            };
            localStorage.setItem(SESSION_KEY, JSON.stringify(session));
            this.sessionSubject.next(session);
            this.isLoggedInSubject.next(true);
          }
        }),
      );
  }

  logout(): void {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(SESSION_KEY);
    this.sessionSubject.next(null);
    this.isLoggedInSubject.next(false);
    this.router.navigate(['/login']);
  }

  getToken(): string | null {
    return localStorage.getItem(TOKEN_KEY);
  }

  hasToken(): boolean {
    return !!this.getToken();
  }

  getSession(): AdminSession | null {
    return this.sessionSubject.value ?? this.readSession();
  }

  /** True if the user may open this portal page key. */
  canAccess(page: string): boolean {
    const s = this.getSession();
    if (!s) return false;
    if (s.staffRole === 'SUPER_ADMIN') return true;
    return (s.pages ?? []).includes(page);
  }

  isSuperAdmin(): boolean {
    return this.getSession()?.staffRole === 'SUPER_ADMIN';
  }

  /** First allowed route after login. */
  homeRoute(): string {
    const s = this.getSession();
    if (!s) return '/login';
    if (s.staffRole === 'SUPER_ADMIN' || s.pages.includes('dashboard')) {
      return '/';
    }
    const first = s.pages[0];
    if (!first || first === 'dashboard') return '/';
    return `/${first}`;
  }

  private readSession(): AdminSession | null {
    try {
      const raw = localStorage.getItem(SESSION_KEY);
      if (!raw) return null;
      return JSON.parse(raw) as AdminSession;
    } catch {
      return null;
    }
  }
}
