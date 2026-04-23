import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { UserService, User } from '../../core/services/user.service';

@Component({
  selector: 'app-users',
  standalone: true,
  imports: [CommonModule],
  providers: [UserService],
  template: `
    <div class="card shadow-sm border-0">
      <div class="card-header bg-white py-3 d-flex justify-content-between align-items-center border-bottom-0">
        <h4 class="mb-0 fw-bold text-dark">Platform Users</h4>
        <span class="badge bg-primary-subtle text-primary rounded-pill px-3 py-2">
          {{ users.length }} Total Users
        </span>
      </div>
      <div class="card-body">
        <div class="table-responsive">
          <table class="table table-hover align-middle mb-0">
            <thead class="bg-light">
              <tr>
                <th class="border-0 px-4 py-3">User</th>
                <th class="border-0 py-3">Role</th>
                <th class="border-0 py-3">Phone Number</th>
                <th class="border-0 py-3">Registration Status</th>
                <th class="border-0 py-3 text-end px-4">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr *ngFor="let user of users" class="border-bottom">
                <td class="px-4 py-3">
                  <div class="d-flex align-items-center">
                    <div class="avatar-sm rounded-circle bg-light d-flex align-items-center justify-content-center me-3" style="width: 40px; height: 40px;">
                      <span class="text-primary fw-bold">{{ user.name ? user.name.charAt(0) : 'U' }}</span>
                    </div>
                    <div>
                      <h6 class="mb-0 fw-semibold">{{ user.name || 'Anonymous User' }}</h6>
                      <small class="text-muted">Joined {{ user.createdAt | date:'mediumDate' }}</small>
                    </div>
                  </div>
                </td>
                <td>
                  <span class="badge rounded-pill" 
                    [ngClass]="{'bg-info-subtle text-info': user.role === 'ADMIN', 'bg-secondary-subtle text-secondary': user.role !== 'ADMIN'}">
                    {{ user.role }}
                  </span>
                </td>
                <td>
                  <code class="text-dark">{{ user.phoneNumber }}</code>
                </td>
                <td>
                  <span [ngClass]="{
                    'bg-warning-subtle text-warning': user.approvalStatus === 'PENDING',
                    'bg-success-subtle text-success': user.approvalStatus === 'APPROVED',
                    'bg-danger-subtle text-danger': user.approvalStatus === 'REJECTED'
                  }" class="badge rounded-pill px-3 py-2">
                    {{ user.approvalStatus }}
                  </span>
                </td>
                <td class="text-end px-4">
                  <div class="d-flex justify-content-end gap-2">
                    <button *ngIf="user.approvalStatus === 'PENDING'" 
                      (click)="approveUser(user.id)" 
                      class="btn btn-sm btn-success rounded-pill px-3">
                      Approve
                    </button>
                    <button (click)="showDetails(user)" class="btn btn-sm btn-light rounded-pill px-3">Details</button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        
        <div *ngIf="users.length === 0" class="text-center py-5">
           <img src="https://cdni.iconscout.com/illustration/premium/thumb/empty-state-2130362-1800926.png" height="120" class="mb-3">
           <p class="text-muted">No users found on the platform.</p>
        </div>
      </div>
    </div>

    <!-- Details Modal -->
    <div *ngIf="selectedUser" class="modal-backdrop fade show"></div>
    <div *ngIf="selectedUser" class="modal fade show d-block" tabindex="-1">
      <div class="modal-dialog modal-dialog-centered modal-lg">
        <div class="modal-content border-0 shadow-lg">
          <div class="modal-header border-0 pb-0">
            <h5 class="modal-title fw-bold text-dark">Professional Profile</h5>
            <button type="button" class="btn-close" (click)="closeDetails()"></button>
          </div>
          <div class="modal-body p-4">
            <div class="d-flex align-items-center mb-4">
              <div class="avatar-lg rounded-circle bg-primary-subtle text-primary d-flex align-items-center justify-content-center me-3" style="width: 64px; height: 64px; font-size: 24px;">
                <span class="fw-bold">{{ selectedUser.name ? selectedUser.name.charAt(0) : 'U' }}</span>
              </div>
              <div>
                <h4 class="mb-1 fw-bold">{{ selectedUser.name || 'Anonymous User' }}</h4>
                <p class="text-muted mb-0"><i class="bi bi-telephone me-2"></i>{{ selectedUser.phoneNumber }}</p>
                <div class="mt-2">
                  <span [ngClass]="{
                    'bg-warning-subtle text-warning': selectedUser.approvalStatus === 'PENDING',
                    'bg-success-subtle text-success': selectedUser.approvalStatus === 'APPROVED',
                    'bg-danger-subtle text-danger': selectedUser.approvalStatus === 'REJECTED'
                  }" class="badge px-3 py-2">
                    Status: {{ selectedUser.approvalStatus }}
                  </span>
                </div>
              </div>
            </div>

            <div class="row g-4">
              <div class="col-md-12">
                <h6 class="fw-bold text-uppercase small text-muted mb-3">Professional Skills & Pricing</h6>
                <div class="table-responsive bg-white rounded border shadow-sm mb-4">
                  <table class="table table-hover align-middle mb-0">
                    <thead class="bg-light">
                      <tr>
                        <th class="small py-3 px-3">Skill Name</th>
                        <th class="small py-3">Hourly Rate</th>
                        <th class="small py-3">Status</th>
                        <th class="small py-3 text-end px-3">Action</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr *ngFor="let skill of selectedUser.talentProfile?.professionalSkills">
                        <td class="px-3 fw-semibold text-dark">{{ skill.name }}</td>
                        <td>₹{{ skill.hourlyRate }}</td>
                        <td>
                          <span [ngClass]="{
                            'bg-warning-subtle text-warning': skill.status === 'PENDING',
                            'bg-success-subtle text-success': skill.status === 'APPROVED',
                            'bg-danger-subtle text-danger': skill.status === 'REJECTED'
                          }" class="badge rounded-pill px-2 py-1 small">
                            {{ skill.status }}
                          </span>
                        </td>
                        <td class="text-end px-3">
                          <div class="btn-group btn-group-sm shadow-sm rounded-pill overflow-hidden">
                            <button *ngIf="skill.status !== 'APPROVED'" (click)="approveSkill(skill.id)" class="btn btn-success" title="Approve Skill"><i class="bi bi-check-lg"></i></button>
                            <button *ngIf="skill.status !== 'REJECTED'" (click)="rejectSkill(skill.id)" class="btn btn-danger" title="Reject Skill"><i class="bi bi-x-lg"></i></button>
                          </div>
                        </td>
                      </tr>
                      <tr *ngIf="!selectedUser.talentProfile?.professionalSkills?.length">
                         <td colspan="4" class="text-center py-4 text-muted small italic">No granular skills registered yet.</td>
                      </tr>
                    </tbody>
                  </table>
                </div>

                <h6 class="fw-bold text-uppercase small text-muted mb-3">Work Experience / Bio</h6>
                <div class="p-3 bg-light rounded border-start border-primary border-4 shadow-sm mb-4">
                  <p class="mb-0 text-dark lh-base" style="white-space: pre-wrap;">
                    {{ selectedUser.talentProfile?.experience || 'No profile biography provided.' }}
                  </p>
                </div>
              </div>
            </div>
          </div>
          <div class="modal-footer border-0 p-4 pt-2">
             <button type="button" class="btn btn-light rounded-pill px-4" (click)='closeDetails()'>Close</button>
             <ng-container *ngIf="selectedUser.approvalStatus === 'PENDING'">
               <button (click)="rejectUser(selectedUser.id); closeDetails()" class="btn btn-outline-danger rounded-pill px-4">Reject User</button>
               <button (click)="approveUser(selectedUser.id); closeDetails()" class="btn btn-success rounded-pill px-4">Approve User Profile</button>
             </ng-container>
             <button *ngIf="selectedUser.approvalStatus === 'REJECTED'" (click)="approveUser(selectedUser.id); closeDetails()" class="btn btn-outline-success rounded-pill px-4">Re-Approve User</button>
             <button *ngIf="selectedUser.approvalStatus === 'APPROVED'" (click)="rejectUser(selectedUser.id); closeDetails()" class="btn btn-outline-danger rounded-pill px-4">Revoke User Approval</button>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .status-badge {
      display: inline-block;
      width: 8px;
      height: 8px;
      border-radius: 50%;
      margin-right: 8px;
    }
    .avatar-sm {
      font-size: 14px;
    }
    .table th {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      font-weight: 700;
      color: #6c757d;
    }
    .modal-backdrop {
      z-index: 1040;
    }
    .modal {
      z-index: 1050;
      background: rgba(0,0,0,0.2) !important;
    }
    .badge {
      font-weight: 600;
      letter-spacing: 0.3px;
    }
  `]
})
export class UsersComponent implements OnInit {
  private userService = inject(UserService);
  users: User[] = [];
  selectedUser: User | null = null;

  ngOnInit(): void {
    this.loadUsers();
  }

  loadUsers(): void {
    console.log('Angular: Loading users...');
    this.userService.getAll().subscribe({
      next: (users) => {
        console.log('Angular: Users fetched:', users);
        this.users = users;
      },
      error: (err) => {
        console.error('Angular: Failed to fetch users:', err);
      }
    });
  }

  approveUser(id: string): void {
    this.userService.updateApprovalStatus(id, 'APPROVED').subscribe(() => {
      this.loadUsers();
    });
  }

  rejectUser(id: string): void {
    this.userService.updateApprovalStatus(id, 'REJECTED').subscribe(() => {
      this.loadUsers();
    });
  }

  approveSkill(skillId: string): void {
    this.userService.updateSkillStatus(skillId, 'APPROVED').subscribe(() => {
       // Hot update selected user to avoid closing modal
       if (this.selectedUser?.talentProfile?.professionalSkills) {
         const skill = this.selectedUser.talentProfile.professionalSkills.find(s => s.id === skillId);
         if (skill) skill.status = 'APPROVED';
       }
       this.loadUsers();
    });
  }

  rejectSkill(skillId: string): void {
    this.userService.updateSkillStatus(skillId, 'REJECTED').subscribe(() => {
       if (this.selectedUser?.talentProfile?.professionalSkills) {
         const skill = this.selectedUser.talentProfile.professionalSkills.find(s => s.id === skillId);
         if (skill) skill.status = 'REJECTED';
       }
       this.loadUsers();
    });
  }

  showDetails(user: User): void {
    this.selectedUser = user;
  }

  closeDetails(): void {
    this.selectedUser = null;
  }
}
