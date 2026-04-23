import { Component, inject } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../services/auth.service';

@Component({
  selector: 'app-layout',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, CommonModule],
  template: `
    <div class="d-flex" style="min-height: 100vh;">
      <!-- Sidebar -->
      <div class="sidebar bg-dark text-white p-3" style="width: 250px;">
        <h3 class="mb-4 text-center">Gixbee Admin</h3>
        <ul class="nav flex-column">
          <li class="nav-item mb-2">
            <a class="nav-link text-white" routerLink="/" routerLinkActive="active" [routerLinkActiveOptions]="{exact: true}">
              <i class="bi bi-speedometer2 me-2"></i> Dashboard
            </a>
          </li>
          <li class="nav-item mb-2">
            <a class="nav-link text-white" routerLink="/master-entries" routerLinkActive="active">
              <i class="bi bi-list-columns-reverse me-2"></i> Master Entries
            </a>
          </li>
          <li class="nav-item mb-2">
            <a class="nav-link text-white" routerLink="/businesses" routerLinkActive="active">
              <i class="bi bi-shop me-2"></i> Businesses
            </a>
          </li>
          <li class="nav-item mb-2">
            <a class="nav-link text-white" routerLink="/users" routerLinkActive="active">
              <i class="bi bi-people me-2"></i> Users
            </a>
          </li>
        </ul>
      </div>

      <!-- Main Content -->
      <div class="flex-grow-1 bg-light">
        <nav class="navbar navbar-expand-lg navbar-light bg-white border-bottom px-4">
          <div class="container-fluid">
            <span class="navbar-brand mb-0 h1">Admin Dashboard</span>
            <div class="d-flex align-items-center">
              <span class="me-3">SuperAdmin</span>
              <button class="btn btn-outline-danger btn-sm" (click)="onLogout()">Logout</button>
            </div>
          </div>
        </nav>

        <div class="p-4">
          <router-outlet></router-outlet>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .nav-link.active {
      background-color: rgba(255, 255, 255, 0.1);
      border-radius: 4px;
      font-weight: bold;
    }
  `]
})
export class LayoutComponent {
  private authService = inject(AuthService);

  onLogout() {
    this.authService.logout();
  }
}
