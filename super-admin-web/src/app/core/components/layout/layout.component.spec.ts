import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { AuthService } from '../../services/auth.service';
import { LayoutComponent } from './layout.component';

describe('Admin navigation rendering', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [LayoutComponent],
      providers: [
        provideRouter([]),
        {
          provide: AuthService,
          useValue: {
            homeRoute: () => '/',
            canAccess: () => true,
            getSession: () => ({ displayName: 'Admin', staffRole: 'SUPER_ADMIN' }),
            logout: () => {},
          },
        },
      ],
    }).compileComponents();
  });

  it('preserves focused navigation links across screen updates', () => {
    const fixture = TestBed.createComponent(LayoutComponent);
    fixture.detectChanges();
    const element: HTMLElement = fixture.nativeElement;
    const link = element.querySelector<HTMLAnchorElement>('.gx-nav-link')!;
    link.focus();

    fixture.detectChanges();
    fixture.detectChanges();

    expect(element.querySelector('.gx-nav-link')).toBe(link);
    expect(document.activeElement).toBe(link);
  });

  it('updates search results and settles without recreating the filtered links', () => {
    const fixture = TestBed.createComponent(LayoutComponent);
    fixture.detectChanges();
    fixture.componentInstance.navQuery.set('Bookings');
    fixture.detectChanges();
    const element: HTMLElement = fixture.nativeElement;
    const link = element.querySelector('.gx-nav-link');
    expect(element.querySelectorAll('.gx-nav-link').length).toBe(1);
    expect(link?.textContent).toContain('Bookings');

    fixture.detectChanges();
    expect(element.querySelector('.gx-nav-link')).toBe(link);
  });
});
