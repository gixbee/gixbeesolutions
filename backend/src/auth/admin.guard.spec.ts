import { ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AdminGuard } from './admin.guard';
import { UserRole } from '../users/user.entity';
import { AdminStaffRole } from '../admin-staff/admin-staff.entity';

/**
 * AdminGuard runs after JwtAuthGuard and gates a route on req.user.role===ADMIN,
 * plus optional @RequireAdminPage metadata for operator page ACL.
 */
function ctx(user: any) {
  return {
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
    getHandler: () => ({}),
    getClass: () => ({}),
  } as any;
}

function makeGuard(requiredPages?: string[] | undefined) {
  const reflector = {
    getAllAndOverride: jest.fn().mockReturnValue(requiredPages),
  } as unknown as Reflector;
  return new AdminGuard(reflector);
}

describe('AdminGuard', () => {
  it('allows a request whose JWT carries the ADMIN role (no page metadata)', () => {
    const guard = makeGuard(undefined);
    expect(
      guard.canActivate(ctx({ userId: 'admin-001', role: UserRole.ADMIN })),
    ).toBe(true);
  });

  it('rejects a non-admin (e.g. CUSTOMER) token', () => {
    const guard = makeGuard(undefined);
    expect(() =>
      guard.canActivate(ctx({ userId: 'u1', role: UserRole.CUSTOMER })),
    ).toThrow(ForbiddenException);
  });

  it('rejects a request with no authenticated user', () => {
    const guard = makeGuard(undefined);
    expect(() => guard.canActivate(ctx(undefined))).toThrow(ForbiddenException);
  });

  it('rejects a user object missing a role', () => {
    const guard = makeGuard(undefined);
    expect(() => guard.canActivate(ctx({ userId: 'u1' }))).toThrow(
      ForbiddenException,
    );
  });

  it('allows SUPER_ADMIN even when page metadata is set', () => {
    const guard = makeGuard(['users']);
    expect(
      guard.canActivate(
        ctx({
          userId: 'sa',
          role: UserRole.ADMIN,
          staffRole: AdminStaffRole.SUPER_ADMIN,
          pages: [],
        }),
      ),
    ).toBe(true);
  });

  it('allows an OPERATOR whose JWT pages include a required page', () => {
    const guard = makeGuard(['bookings', 'disputes']);
    expect(
      guard.canActivate(
        ctx({
          userId: 'op',
          role: UserRole.ADMIN,
          staffRole: AdminStaffRole.OPERATOR,
          pages: ['bookings'],
        }),
      ),
    ).toBe(true);
  });

  it('rejects an OPERATOR missing the required page', () => {
    const guard = makeGuard(['users']);
    expect(() =>
      guard.canActivate(
        ctx({
          userId: 'op',
          role: UserRole.ADMIN,
          staffRole: AdminStaffRole.OPERATOR,
          pages: ['bookings'],
        }),
      ),
    ).toThrow(ForbiddenException);
  });
});
