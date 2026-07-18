import { Component, inject } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../services/auth.service';

interface NavItem {
  page: string;
  path: string;
  label: string;
  icon: string;
  exact?: boolean;
}

@Component({
  selector: 'app-layout',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, CommonModule],
  template: `
    <div class="d-flex" style="min-height: 100vh;">
      <aside class="gx-sidebar">
        <div class="gx-sidebar-brand">gixbee<span class="accent">·admin</span></div>

        <ng-container *ngFor="let section of visibleSections">
          <div class="gx-nav-section">{{ section.title }}</div>
          <a *ngFor="let item of section.items"
             class="gx-nav-link"
             [routerLink]="item.path"
             routerLinkActive="active"
             [routerLinkActiveOptions]="{ exact: !!item.exact }">
            <i class="bi" [ngClass]="item.icon"></i> {{ item.label }}
          </a>
        </ng-container>
      </aside>

      <div class="flex-grow-1 d-flex flex-column" style="min-width: 0;">
        <header class="gx-topbar">
          <span class="title">Gixbee Operations</span>
          <div class="d-flex align-items-center gap-3">
            <span class="gx-admin-chip">
              <span class="avatar">{{ initials }}</span>
              {{ displayName }}
              <span class="badge bg-dark ms-2" style="font-size: 10px;">{{ staffRole }}</span>
            </span>
            <button class="btn btn-sm btn-outline-danger" (click)="onLogout()">
              <i class="bi bi-box-arrow-right me-1"></i>Logout
            </button>
          </div>
        </header>

        <main class="gx-page flex-grow-1 w-100">
          <router-outlet></router-outlet>
        </main>
      </div>
    </div>
  `,
})
export class LayoutComponent {
  private authService = inject(AuthService);

  private readonly sections: { title: string; items: NavItem[] }[] = [
    {
      title: 'Overview',
      items: [
        { page: 'dashboard', path: '/', label: 'Dashboard', icon: 'bi-speedometer2', exact: true },
      ],
    },
    {
      title: 'Operations',
      items: [
        { page: 'bookings', path: '/bookings', label: 'Bookings', icon: 'bi-calendar-check' },
        { page: 'verifications', path: '/verifications', label: 'Verifications', icon: 'bi-patch-check' },
        { page: 'disputes', path: '/disputes', label: 'Disputes', icon: 'bi-flag' },
        { page: 'support', path: '/support', label: 'Support', icon: 'bi-life-preserver' },
        { page: 'businesses', path: '/businesses', label: 'Businesses', icon: 'bi-shop' },
      ],
    },
    {
      title: 'Catalog',
      items: [
        { page: 'master-entries', path: '/master-entries', label: 'Master Entries', icon: 'bi-list-columns-reverse' },
        { page: 'cities', path: '/cities', label: 'Cities', icon: 'bi-geo-alt' },
      ],
    },
    {
      title: 'People',
      items: [
        { page: 'users', path: '/users', label: 'Users', icon: 'bi-people' },
        { page: 'staff', path: '/staff', label: 'Admin staff', icon: 'bi-shield-lock' },
      ],
    },
  ];

  get visibleSections() {
    return this.sections
      .map((s) => ({
        title: s.title,
        items: s.items.filter((i) => this.authService.canAccess(i.page)),
      }))
      .filter((s) => s.items.length > 0);
  }

  get displayName() {
    return this.authService.getSession()?.displayName || 'Admin';
  }

  get staffRole() {
    return this.authService.getSession()?.staffRole || 'ADMIN';
  }

  get initials() {
    const n = this.displayName.trim();
    return (n.charAt(0) || 'A').toUpperCase();
  }

  onLogout() {
    this.authService.logout();
  }
}
