import { CanActivate, ExecutionContext, Injectable, ForbiddenException } from '@nestjs/common';
import { UserRole } from '../users/user.entity';

/**
 * Role gate for super-admin-only routes. Runs AFTER JwtAuthGuard, which
 * authenticates the request and populates `req.user` (see JwtStrategy.validate,
 * which returns `{ userId, phoneNumber, role }`). Use them together and in order:
 *
 *   @UseGuards(JwtAuthGuard, AdminGuard)
 *
 * The super-admin portal obtains an ADMIN-role JWT from POST /auth/admin-login;
 * a normal consumer JWT (issued via OTP) carries CUSTOMER/WORKER and is rejected
 * here, so a valid-but-non-admin token cannot mutate master data.
 */
@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest();
    if (req.user?.role !== UserRole.ADMIN) {
      throw new ForbiddenException('Admin access required');
    }
    return true;
  }
}
