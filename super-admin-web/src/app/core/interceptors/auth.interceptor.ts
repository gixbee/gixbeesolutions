import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { DOCUMENT } from '@angular/common';
import { catchError, throwError } from 'rxjs';
import { AuthService } from '../services/auth.service';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const document = inject(DOCUMENT);
  const url = new URL(req.url, document.baseURI);
  const isApi = url.origin === document.location.origin && url.pathname.startsWith('/api/');
  const isLogin = url.pathname === '/api/auth/admin-login';
  if (!isApi || isLogin) return next(req);

  const token = authService.getToken();
  const authReq = token ? req.clone({
      setHeaders: {
        Authorization: `Bearer ${token}`
      }
    }) : req;
  return next(authReq).pipe(catchError(error => {
    const currentToken = authService.getToken();
    if (error.status === 401 && (!currentToken || currentToken === token)) {
      authService.logout();
    }
    return throwError(() => error);
  }));
};
