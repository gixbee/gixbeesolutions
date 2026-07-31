import { ForbiddenException } from '@nestjs/common';
import { AdminGuard } from './admin.guard';
import { UserRole } from '../users/user.entity';

/**
 * AdminGuard runs after JwtAuthGuard and gates a route on req.user.role===ADMIN.
 * These tests feed a fake ExecutionContext carrying different req.user shapes.
 */
function ctx(user: any) {
  return {
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  } as any;
}

describe('AdminGuard', () => {
  const guard = new AdminGuard();

  it('allows a request whose JWT carries the ADMIN role', () => {
    expect(
      guard.canActivate(ctx({ userId: 'admin-001', role: UserRole.ADMIN })),
    ).toBe(true);
  });

  it('rejects a non-admin (e.g. CUSTOMER) token', () => {
    expect(() =>
      guard.canActivate(ctx({ userId: 'u1', role: UserRole.CUSTOMER })),
    ).toThrow(ForbiddenException);
  });

  it('rejects a request with no authenticated user', () => {
    expect(() => guard.canActivate(ctx(undefined))).toThrow(ForbiddenException);
  });

  it('rejects a user object missing a role', () => {
    expect(() => guard.canActivate(ctx({ userId: 'u1' }))).toThrow(
      ForbiddenException,
    );
  });
});
