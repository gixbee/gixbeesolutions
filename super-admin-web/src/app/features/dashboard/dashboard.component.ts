import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { UserService } from '../../core/services/user.service';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="dashboard-container">
      <div class="row g-4 mb-4">
        <!-- Stats Cards -->
        <div class="col-md-3">
          <div class="card stat-card bg-primary text-white h-100 border-0 shadow-sm">
            <div class="card-body">
              <div class="d-flex justify-content-between align-items-center mb-3">
                <i class="bi bi-people fs-1 opacity-50"></i>
                <span class="fs-4 fw-bold">{{ summary?.totalUsers || 0 }}</span>
              </div>
              <h6 class="card-title mb-0 opacity-75">Total Customers</h6>
            </div>
          </div>
        </div>
        <div class="col-md-3">
          <div class="card stat-card bg-success text-white h-100 border-0 shadow-sm">
            <div class="card-body">
              <div class="d-flex justify-content-between align-items-center mb-3">
                <i class="bi bi-person-badge fs-1 opacity-50"></i>
                <span class="fs-4 fw-bold">{{ summary?.totalWorkers || 0 }}</span>
              </div>
              <h6 class="card-title mb-0 opacity-75">Active Workers</h6>
            </div>
          </div>
        </div>
        <div class="col-md-3">
          <div class="card stat-card bg-info text-white h-100 border-0 shadow-sm">
            <div class="card-body">
              <div class="d-flex justify-content-between align-items-center mb-3">
                <i class="bi bi-calendar-check fs-1 opacity-50"></i>
                <span class="fs-4 fw-bold">{{ summary?.totalBookings || 0 }}</span>
              </div>
              <h6 class="card-title mb-0 opacity-75">Total Bookings</h6>
            </div>
          </div>
        </div>
        <div class="col-md-3">
          <div class="card stat-card bg-warning text-dark h-100 border-0 shadow-sm">
            <div class="card-body">
              <div class="d-flex justify-content-between align-items-center mb-3">
                <i class="bi bi-hourglass-split fs-1 opacity-50"></i>
                <span class="fs-4 fw-bold">{{ summary?.pendingApprovals || 0 }}</span>
              </div>
              <h6 class="card-title mb-0 opacity-75">Pending verifications</h6>
            </div>
          </div>
        </div>
      </div>

      <div class="row g-4">
        <!-- Recent Activity -->
        <div class="col-lg-8">
          <div class="card border-0 shadow-sm">
            <div class="card-header bg-white py-3">
              <h5 class="mb-0">Recent User Registrations</h5>
            </div>
            <div class="card-body p-0">
              <div class="table-responsive">
                <table class="table table-hover align-middle mb-0">
                  <thead class="table-light text-muted small">
                    <tr>
                      <th class="ps-4">User</th>
                      <th>Phone</th>
                      <th>Joined</th>
                      <th class="text-end pe-4">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    @for (user of summary?.recentUsers; track user.id) {
                      <tr>
                        <td class="ps-4">
                          <div class="d-flex align-items-center">
                            <img [src]="user.profileImageUrl || 'https://i.pravatar.cc/150'" class="rounded-circle me-3" width="32" height="32">
                            <span class="fw-semibold">{{ user.name }}</span>
                          </div>
                        </td>
                        <td>{{ user.phoneNumber }}</td>
                        <td class="small">{{ user.createdAt | date:'short' }}</td>
                        <td class="text-end pe-4">
                          <span class="badge" [ngClass]="user.isVerified ? 'bg-success-subtle text-success' : 'bg-warning-subtle text-warning'">
                            {{ user.isVerified ? 'Verified' : 'Pending' }}
                          </span>
                        </td>
                      </tr>
                    }
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>

        <!-- Quick Links -->
        <div class="col-lg-4">
          <div class="card border-0 shadow-sm bg-dark text-white h-100">
            <div class="card-body d-flex flex-column justify-content-center text-center py-5">
              <h4 class="mb-3">Ready to dispatch?</h4>
              <p class="opacity-75 mb-4 px-4 text-small">Manage your master service listings and banner carousels for the mobile application.</p>
              <button class="btn btn-outline-light rounded-pill px-4 align-self-center">Management Portal</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .stat-card {
      transition: transform 0.2s;
      border-radius: 12px;
    }
    .stat-card:hover {
      transform: translateY(-5px);
    }
  `]
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
