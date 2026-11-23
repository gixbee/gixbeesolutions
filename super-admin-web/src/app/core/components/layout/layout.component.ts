import { Component, inject, signal, HostListener } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../services/auth.service';
import { FormsModule } from '@angular/forms';
import { NavigationEnd, Router } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

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
  imports: [RouterOutlet, RouterLink, RouterLinkActive, CommonModule, FormsModule],
  template: `
    <a class="gx-skip-link" href="#admin-content">Skip to content</a>
    <div class="gx-admin-shell">
      <!-- Backdrop shown only when the mobile drawer is open -->
      <div class="gx-backdrop d-lg-none"
           [class.show]="sidebarOpen()"
           (click)="closeSidebar()"></div>

      <aside id="admin-navigation" class="gx-sidebar" [class.open]="sidebarOpen()" aria-label="Admin navigation">
        <div class="gx-sidebar-brand">
          <a [routerLink]="homeRoute" class="gx-brand-link" (click)="closeSidebar()">
            <span class="gx-brand-mark" aria-hidden="true">g</span>
            <span>gixbee<span class="gx-brand-caption">Admin workspace</span></span>
          </a>
          <button class="gx-sidebar-close d-lg-none" (click)="closeSidebar()" aria-label="Close menu">
            <i class="bi bi-x-lg"></i>
          </button>
        </div>

        <div class="gx-nav-search">
          <i class="bi bi-search" aria-hidden="true"></i>
          <input type="search" placeholder="Find a page…" aria-label="Find an admin page"
                 [ngModel]="navQuery()" (ngModelChange)="navQuery.set($event)">
        </div>
        <nav class="gx-nav-scroll" aria-label="Workspace pages">
        <ng-container *ngFor="let section of filteredSections">
          <div class="gx-nav-section">{{ section.title }}</div>
          <a *ngFor="let item of section.items"
             class="gx-nav-link"
             [routerLink]="item.path"
             routerLinkActive="active"
             ariaCurrentWhenActive="page"
             [routerLinkActiveOptions]="{ exact: !!item.exact }"
             (click)="closeSidebar()">
            <i class="bi" [ngClass]="item.icon"></i> {{ item.label }}
          </a>
        </ng-container>
        @if (!filteredSections.length) {
          <p class="gx-nav-empty">No matching pages.</p>
        }
        </nav>
        <div class="gx-sidebar-footer">
          <span class="avatar">{{ initials }}</span>
          <span><strong>{{ displayName }}</strong><small>{{ roleLabel }}</small></span>
        </div>
      </aside>

      <div class="flex-grow-1 d-flex flex-column" style="min-width: 0;">
        <header class="gx-topbar">
          <div class="d-flex align-items-center gap-2" style="min-width: 0;">
            <button class="gx-menu-toggle d-lg-none" (click)="toggleSidebar()"
                    [attr.aria-expanded]="sidebarOpen()" aria-controls="admin-navigation"
                    [attr.aria-label]="sidebarOpen() ? 'Close menu' : 'Open menu'">
              <i class="bi bi-list"></i>
            </button>
            <div class="gx-topbar-heading">
              <span class="gx-topbar-section">{{ currentSection() }}</span>
              <span class="title text-truncate">{{ currentPage() }}</span>
            </div>
          </div>
          <div class="d-flex align-items-center gap-2 gap-md-3">
            <span class="gx-admin-chip">
              <span class="avatar">{{ initials }}</span>
              <span class="gx-admin-name">{{ displayName }}</span>
            </span>
            <button class="btn btn-sm btn-outline-secondary" (click)="onLogout()" aria-label="Sign out">
              <i class="bi bi-box-arrow-right me-1"></i><span class="d-none d-sm-inline">Sign out</span>
            </button>
          </div>
        </header>

        <main id="admin-content" tabindex="-1" class="gx-page flex-grow-1 w-100">
          <router-outlet></router-outlet>
        </main>
      </div>
    </div>
  `,
})
export class LayoutComponent {
  private authService = inject(AuthService);
  private router = inject(Router);
  readonly homeRoute = this.authService.homeRoute();
  readonly navQuery = signal('');
  readonly currentPage = signal('Dashboard');
  readonly currentSection = signal('Overview');

  constructor() {
    this.updatePage();
    this.router.events.pipe(takeUntilDestroyed()).subscribe(event => {
      if (event instanceof NavigationEnd) {
        this.updatePage();
        this.closeSidebar();
      }
    });
  }

  private updatePage() {
    const path = this.router.url.split(/[?#]/)[0];
    for (const section of this.visibleSections) {
      const item = section.items.find(item =>
        path === item.path || (item.path !== '/' && path.startsWith(item.path + '/')));
      if (item) {
        this.currentPage.set(item.label);
        this.currentSection.set(section.title);
        return;
      }
    }
    this.currentPage.set('Workspace');
    this.currentSection.set('Gixbee');
  }

  get filteredSections() {
    const query = this.navQuery().trim().toLowerCase();
    return this.visibleSections.map(section => ({
      ...section,
      items: section.items.filter(item =>
        (section.title + ' ' + item.label).toLowerCase().includes(query)),
    })).filter(section => section.items.length > 0);
  }

  get roleLabel() {
    return this.staffRole === 'SUPER_ADMIN' ? 'Super admin' : 'Operator';
  }

  @HostListener('document:keydown.escape')
  onEscape() {
    this.closeSidebar();
  }

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
      title: 'Master data',
      items: [
        { page: 'master-entries', path: '/hiring-catalogue', label: 'Hiring catalogue', icon: 'bi-diagram-2' },
        { page: 'master-entries', path: '/service-catalogue', label: 'Service catalogue', icon: 'bi-tools' },
        { page: 'master-entries', path: '/location-master', label: 'Location master', icon: 'bi-map' },
        { page: 'cities', path: '/cities', label: 'Serviceable areas', icon: 'bi-geo-alt' },
        { page: 'master-entries', path: '/rental-catalogue', label: 'Rental catalogue', icon: 'bi-box-seam' },
        { page: 'master-entries', path: '/event-catalogue', label: 'Event catalogue', icon: 'bi-calendar-event' },
        { page: 'pricing-policies', path: '/pricing-policies', label: 'Pricing & policies', icon: 'bi-currency-rupee' },
        { page: 'operational-settings', path: '/operational-settings', label: 'Operational settings', icon: 'bi-sliders' },
        { page: 'master-entries', path: '/content-reasons', label: 'Content & reasons', icon: 'bi-chat-left-text' },
        { page: 'master-entries', path: '/master-entries', label: 'Master entries (all)', icon: 'bi-list-columns-reverse' },
        { page: 'businesses', path: '/rentals-flow', label: 'Rental flow (ops)', icon: 'bi-diagram-3' },
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
