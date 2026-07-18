import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { UserService } from '../../core/services/user.service';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="gx-page-title">Dashboard</div>
    <div class="gx-page-sub">Platform overview at a glance.</div>

    <div class="row g-3 mb-4">
      <div class="col-md-3">
        <div class="gx-stat">
          <div class="label">Total Users</div>
          <div class="value">{{ summary?.totalUsers || 0 }}</div>
        </div>
      </div>
      <div class="col-md-3">
        <div class="gx-stat">
          <div class="label">Active Workers</div>
          <div class="value">{{ summary?.totalWorkers || 0 }}</div>
        </div>
      </div>
      <div class="col-md-3">
        <div class="gx-stat">
          <div class="label">Total Bookings</div>
          <div class="value">{{ summary?.totalBookings || 0 }}</div>
        </div>
      </div>
      <div class="col-md-3">
        <a routerLink="/verifications" style="text-decoration: none">
          <div class="gx-stat" style="border-left: 3px solid var(--gx-warning)">
            <div class="label">Pending Verifications</div>
            <div class="value">{{ summary?.pendingApprovals || 0 }}</div>
          </div>
        </a>
      </div>
    </div>

    <div class="row g-3">
      <div class="col-lg-8">
        <div class="card">
          <div class="card-header py-3"><h5 class="mb-0">Recent User Registrations</h5></div>
          <div class="table-responsive">
            <table class="table table-hover align-middle">
              <thead>
                <tr>
                  <th>User</th>
                  <th>Phone</th>
                  <th>Joined</th>
                  <th class="text-end">Status</th>
                </tr>
              </thead>
              <tbody>
                @for (user of summary?.recentUsers; track user.id) {
                  <tr>
                    <td>
                      <div class="d-flex align-items-center">
                        <img [src]="user.profileImageUrl || 'https://i.pravatar.cc/150'" class="rounded-circle me-2" width="28" height="28" alt="">
                        <span class="fw-semibold">{{ user.name || 'Unnamed' }}</span>
                      </div>
                    </td>
                    <td>{{ user.phoneNumber }}</td>
                    <td>{{ user.createdAt | date:'MMM d, HH:mm' }}</td>
                    <td class="text-end">
                      <span class="badge" [ngClass]="user.isVerified ? 'bg-success' : 'bg-warning'">
                        {{ user.isVerified ? 'Verified' : 'Pending' }}
                      </span>
                    </td>
                  </tr>
                } @empty {
                  <tr><td colspan="4"><div class="gx-empty"><i class="bi bi-people"></i>No recent registrations.</div></td></tr>
                }
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div class="col-lg-4">
        <div class="card h-100">
          <div class="card-header py-3"><h5 class="mb-0">Quick actions</h5></div>
          <div class="list-group list-group-flush">
            <a routerLink="/bookings" class="list-group-item list-group-item-action d-flex align-items-center gap-2">
              <i class="bi bi-calendar-check text-primary"></i> Monitor live bookings
            </a>
            <a routerLink="/verifications" class="list-group-item list-group-item-action d-flex align-items-center gap-2">
              <i class="bi bi-patch-check text-primary"></i> Review worker verifications
            </a>
            <a routerLink="/disputes" class="list-group-item list-group-item-action d-flex align-items-center gap-2">
              <i class="bi bi-flag text-primary"></i> Handle disputes
            </a>
            <a routerLink="/businesses" class="list-group-item list-group-item-action d-flex align-items-center gap-2">
              <i class="bi bi-shop text-primary"></i> Moderate businesses
            </a>
            <a routerLink="/master-entries" class="list-group-item list-group-item-action d-flex align-items-center gap-2">
              <i class="bi bi-list-columns-reverse text-primary"></i> Edit banners & deals
            </a>
            <a routerLink="/cities" class="list-group-item list-group-item-action d-flex align-items-center gap-2">
              <i class="bi bi-geo-alt text-primary"></i> Manage cities
            </a>
          </div>
        </div>
      </div>
    </div>
  `
})
export class DashboardComponent implements OnInit {
  private userService = inject(UserService);
  summary: any = null;

  ngOnInit() {
    this.userService.getSummary().subscribe(res => {
      this.summary = res;
    });
  }
}
