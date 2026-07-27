import { Routes } from '@angular/router';
import { LayoutComponent } from './core/components/layout/layout.component';
import { MasterEntriesComponent } from './features/master-entries/master-entries.component';
import { UsersComponent } from './features/users/users.component';
import { BusinessesComponent } from './features/businesses/businesses.component';
import { CitiesComponent } from './features/cities/cities.component';
import { VerificationsComponent } from './features/verifications/verifications.component';
import { DisputesComponent } from './features/disputes/disputes.component';
import { StrikesComponent } from './features/strikes/strikes.component';
import { BookingsComponent } from './features/bookings/bookings.component';
import { SupportComponent } from './features/support/support.component';
import { LoginComponent } from './features/auth/login/login.component';
import { DashboardComponent } from './features/dashboard/dashboard.component';
import { StaffComponent } from './features/staff/staff.component';
import { LogsComponent } from './features/logs/logs.component';
import { MonitoringComponent } from './features/monitoring/monitoring.component';
import { InfrastructureComponent } from './features/infrastructure/infrastructure.component';
import { authGuard } from './core/guards/auth.guard';
import { pageGuard } from './core/guards/page.guard';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  {
    path: '',
    component: LayoutComponent,
    canActivate: [authGuard],
    children: [
      { path: '', component: DashboardComponent, canActivate: [pageGuard], data: { page: 'dashboard' } },
      { path: 'bookings', component: BookingsComponent, canActivate: [pageGuard], data: { page: 'bookings' } },
      { path: 'verifications', component: VerificationsComponent, canActivate: [pageGuard], data: { page: 'verifications' } },
      { path: 'disputes', component: DisputesComponent, canActivate: [pageGuard], data: { page: 'disputes' } },
      // Strike appeals share the disputes permission — same operational job
      // (reviewing worker conduct), so no staff-permission change needed.
      { path: 'strikes', component: StrikesComponent, canActivate: [pageGuard], data: { page: 'disputes' } },
      { path: 'support', component: SupportComponent, canActivate: [pageGuard], data: { page: 'support' } },
      { path: 'master-entries', component: MasterEntriesComponent, canActivate: [pageGuard], data: { page: 'master-entries' } },
      { path: 'cities', component: CitiesComponent, canActivate: [pageGuard], data: { page: 'cities' } },
      { path: 'users', component: UsersComponent, canActivate: [pageGuard], data: { page: 'users' } },
      { path: 'businesses', component: BusinessesComponent, canActivate: [pageGuard], data: { page: 'businesses' } },
      { path: 'staff', component: StaffComponent, canActivate: [pageGuard], data: { page: 'staff' } },
      { path: 'logs', component: LogsComponent, canActivate: [pageGuard], data: { page: 'logs' } },
      { path: 'monitoring', component: MonitoringComponent, canActivate: [pageGuard], data: { page: 'monitoring' } },
      { path: 'infrastructure', component: InfrastructureComponent, canActivate: [pageGuard], data: { page: 'monitoring' } },
    ],
  },
  { path: '**', redirectTo: '' },
];
