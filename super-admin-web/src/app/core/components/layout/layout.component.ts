import { Component, inject, signal, HostListener } from '@angular/core';
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
      <!-- Backdrop shown only when the mobile drawer is open -->
      <div class="gx-backdrop d-lg-none"
           [class.show]="sidebarOpen()"
           (click)="closeSidebar()"></div>

      <aside class="gx-sidebar" [class.open]="sidebarOpen()">
        <div class="gx-sidebar-brand">
          gixbee<span class="accent">·admin</span>
          <button class="gx-sidebar-close d-lg-none" (click)="closeSidebar()" aria-label="Close menu">
            <i class="bi bi-x-lg"></i>
          </button>
        </div>

        <ng-container *ngFor="let section of visibleSections">
          <div class="gx-nav-section">{{ section.title }}</div>
          <a *ngFor="let item of section.items"
             class="gx-nav-link"
             [routerLink]="item.path"
             routerLinkActive="active"
             [routerLinkActiveOptions]="{ exact: !!item.exact }"
             (click)="closeSidebar()">
            <i class="bi" [ngClass]="item.icon"></i> {{ item.label }}
          </a>
        </ng-container>
      </aside>

      <div class="flex-grow-1 d-flex flex-column" style="min-width: 0;">
        <header class="gx-topbar">
          <div class="d-flex align-items-center gap-2" style="min-width: 0;">
            <button class="gx-menu-toggle d-lg-none" (click)="toggleSidebar()" aria-label="Open menu">
              <i class="bi bi-list"></i>
            </button>
            <span class="title text-truncate">Gixbee Operations</span>
          </div>
          <div class="d-flex align-items-center gap-2 gap-md-3">
            <span class="gx-admin-chip">
              <span class="avatar">{{ initials }}</span>
              <span class="gx-admin-name">{{ displayName }}</span>
              <span class="badge bg-dark ms-2 gx-admin-role" style="font-size: 10px;">{{ staffRole }}</span>
            </span>
            <button class="btn btn-sm btn-outline-danger" (click)="onLogout()">
              <i class="bi bi-box-arrow-right me-1"></i><span class="d-none d-sm-inline">Logout</span>
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

  /** Whether the off-canvas sidebar drawer is open (mobile only). */
  readonly sidebarOpen = signal(false);

  toggleSidebar() {
    this.sidebarOpen.update((v) => !v);
  }

  closeSidebar() {
    this.sidebarOpen.set(false);
  }

  /** Auto-close the drawer if the viewport grows back to desktop width. */
  @HostListener('window:resize')
  onResize() {
    if (typeof window !== 'undefined' && window.innerWidth >= 992 && this.sidebarOpen()) {
      this.sidebarOpen.set(false);
    }
  }

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
        { page: 'disputes', path: '/strikes', label: 'Strike Appeals', icon: 'bi-hammer' },
        { page: 'support', path: '/support', label: 'Support', icon: 'bi-life-preserver' },
        { page: 'businesses', path: '/businesses', label: 'Businesses', icon: 'bi-shop' },
      ],
    },
    {
      title: 'Catalog',
      items: [
        { page: 'master-entries', path: '/master-entries', label: 'Master Entries', icon: 'bi-list-columns-reverse' },
        { page: 'cities', path: '/cities', label: 'Cities', icon: 'bi-geo-alt' },
        { page: 'businesses', path: '/rentals-flow', label: 'Rental flow', icon: 'bi-diagram-3' },
      ],
    },
    {
      title: 'People',
      items: [
        { page: 'users', path: '/users', label: 'Users', icon: 'bi-people' },
        { page: 'staff', path: '/staff', label: 'Admin staff', icon: 'bi-shield-lock' },
      ],
    },
    {
      title: 'System',
      items: [
        { page: 'monitoring', path: '/monitoring', label: 'Monitoring', icon: 'bi-cpu' },
        { page: 'logs', path: '/logs', label: 'Logs', icon: 'bi-journal-text' },
      ],
    },
  ];

  readonly visibleSections = this.sections
    .map((s) => ({
      title: s.title,
      items: s.items.filter((i) => this.authService.canAccess(i.page)),
    }))
    .filter((s) => s.items.length > 0);

  readonly displayName =
    this.authService.getSession()?.displayName || 'Admin';

  readonly staffRole =
    this.authService.getSession()?.staffRole || 'ADMIN';

  readonly initials = (() => {
    const n = this.displayName.trim();
    return (n.charAt(0) || 'A').toUpperCase();
  })();

  onLogout() {
    this.authService.logout();
  }
}
