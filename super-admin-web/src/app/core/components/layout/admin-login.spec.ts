import { TestBed } from '@angular/core/testing';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { NavigationEnd, provideRouter, Router } from '@angular/router';
import { filter, firstValueFrom, take } from 'rxjs';
import { RouterTestingHarness } from '@angular/router/testing';
import { LayoutComponent } from './layout.component';
import { LoginComponent } from '../../../features/auth/login/login.component';
import { DashboardComponent } from '../../../features/dashboard/dashboard.component';
import { authGuard } from '../../guards/auth.guard';
import { pageGuard } from '../../guards/page.guard';
import { authInterceptor } from '../../interceptors/auth.interceptor';

describe('Admin sign-in navigation', () => {
  afterEach(() => {
    TestBed.inject(HttpTestingController).verify();
    localStorage.removeItem('gixbee_admin_token');
    localStorage.removeItem('gixbee_admin_session');
  });

  it('renders the dashboard after a successful login response', async () => {
    await TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
        provideRouter([
          { path: 'login', component: LoginComponent },
          {
            path: '', component: LayoutComponent, canActivate: [authGuard],
            children: [{ path: '', component: DashboardComponent, canActivate: [pageGuard], data: { page: 'dashboard' } }],
          },
        ]),
      ],
    }).compileComponents();
    const harness = await RouterTestingHarness.create();
    const login = await harness.navigateByUrl('/login', LoginComponent);
    const http = TestBed.inject(HttpTestingController);
    login.username = 'test-admin';
    login.password = 'test-password';
    const router = TestBed.inject(Router);
    const navigation = firstValueFrom(router.events.pipe(
      filter(event => event instanceof NavigationEnd), take(1),
    ));
    login.onSubmit();

    const token = 'test.' + btoa(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 3600 })) + '.test';
    http.expectOne('/api/auth/admin-login').flush({
      accessToken: token, staffRole: 'SUPER_ADMIN', pages: ['dashboard'],
      displayName: 'Test admin', username: 'test-admin',
    });
    await navigation;
    harness.detectChanges();
    http.expectOne('/api/admin-user-list/summary').flush({
      totalUsers: 1, totalWorkers: 0, totalBookings: 0, pendingApprovals: 0, recentUsers: [],
    });
    await harness.fixture.whenStable();
    harness.detectChanges();

    expect(TestBed.inject(Router).url).toBe('/');
    expect(harness.routeNativeElement?.querySelector('h1')?.textContent).toContain('Dashboard');
    expect(harness.routeNativeElement?.querySelector('nav .active')?.textContent).toContain('Dashboard');
  });
});
