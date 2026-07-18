import { CanActivateFn, Router, ActivatedRouteSnapshot } from '@angular/router';
import { inject } from '@angular/core';
import { AuthService } from '../services/auth.service';

/**
 * Requires a token AND that the staff user is allowed this route's `data.page`.
 * Routes without `data.page` only require login.
 */
export const pageGuard: CanActivateFn = (route: ActivatedRouteSnapshot) => {
  const auth = inject(AuthService);
  const router = inject(Router);

  if (!auth.hasToken()) {
    router.navigate(['/login']);
    return false;
  }

  const page = route.data?.['page'] as string | undefined;
  if (!page) return true;

  if (auth.canAccess(page)) return true;

  router.navigateByUrl(auth.homeRoute());
  return false;
};
