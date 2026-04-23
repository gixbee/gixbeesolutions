import { Routes } from '@angular/router';
import { LayoutComponent } from './core/components/layout/layout.component';
import { MasterEntriesComponent } from './features/master-entries/master-entries.component';
import { UsersComponent } from './features/users/users.component';
import { BusinessesComponent } from './features/businesses/businesses.component';
import { LoginComponent } from './features/auth/login/login.component';
import { DashboardComponent } from './features/dashboard/dashboard.component';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  {
    path: '',
    component: LayoutComponent,
    canActivate: [authGuard],
    children: [
      { path: '', component: DashboardComponent },
      { path: 'master-entries', component: MasterEntriesComponent },
      { path: 'users', component: UsersComponent },
      { path: 'businesses', component: BusinessesComponent },
    ]
  },
  { path: '**', redirectTo: '' }
];
