import { CanActivateFn, Router } from '@angular/router';
import { inject } from '@angular/core';
import { AuthService } from '../services/auth.service';

export const authGuard: CanActivateFn = () => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (!authService.hasToken()) {
    router.navigate(['/login']);
    return false;
  }

  // Tokens issued before staff RBAC have no session blob — force re-login.
  if (!authService.getSession()) {
    authService.logout();
    return false;
  }

  return true;
};
