import {
  CanActivate,
  ExecutionContext,
  Injectable,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '../users/user.entity';
import { AdminStaffRole } from '../admin-staff/admin-staff.entity';
import { ADMIN_PAGES_KEY } from './require-admin-page.decorator';

/**
 * Role + page gate for super-admin portal routes. Runs AFTER JwtAuthGuard,
 * which populates `req.user` as `{ userId, role, staffRole?, pages? }`.
 *
 *   @UseGuards(JwtAuthGuard, AdminGuard)
 *   @RequireAdminPage('users')
 *
 * - Any non-ADMIN JWT is rejected.
 * - SUPER_ADMIN always allowed.
 * - OPERATOR must have at least one of the required page keys in JWT `pages`.
 * - Routes without `@RequireAdminPage` stay ADMIN-only (any admin JWT) —
 *   use that only for shared shell endpoints like `/admin-staff/me`.
 */
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest();
    if (req.user?.role !== UserRole.ADMIN) {
      throw new ForbiddenException('Admin access required');
    }

    const requiredPages = this.reflector.getAllAndOverride<string[]>(
      ADMIN_PAGES_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (!requiredPages || requiredPages.length === 0) {
      return true;
    }

    if (req.user.staffRole === AdminStaffRole.SUPER_ADMIN) {
      return true;
    }

    const granted: string[] = Array.isArray(req.user.pages)
      ? req.user.pages
      : [];
    if (requiredPages.some((page) => granted.includes(page))) {
      return true;
    }

    throw new ForbiddenException('Insufficient admin page access');
  }
}
