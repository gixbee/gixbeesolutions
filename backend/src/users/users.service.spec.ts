import { NotFoundException } from '@nestjs/common';
import { UsersService } from './users.service';
import { UserApprovalStatus, UserRole } from './user.entity';

/**
 * Unit tests for UsersService — the admin/user-management + profile surface.
 * This is one of the four large, central services Passes 55–68 left WITHOUT a
 * service-level spec (they added a controller spec for it in Pass 63, but never
 * tested the service's own branches). Both repositories are mocked in-memory so
 * each branch toggles deterministically; no database is touched.
 *
 * Coverage:
 * - findById: returns the user, or throws NotFound when absent.
 * - getUserStats: counts the customer's bookings; returns all-zeros when the
 *   user is missing AND swallows any repo error (invalid-UUID guard) into zeros.
 * - updateProfile: NotFound guard + partial-field apply (only defined fields are
 *   written, undefined fields left untouched) + save round-trip.
 * - updateFcmToken: NotFound guard + token write + save.
 * - findAll: ordered list with the talent-profile relations.
 * - updateApprovalStatus: APPROVED auto-verifies + enables worker profile;
 *   REJECTED clears isVerified; PENDING leaves verification flags alone.
 * - updateVerification: true auto-enables hasWorkerProfile; false leaves it.
 * - getSystemSummary: aggregates the four counts + recent-users list.
 */

function makeService(opts: { user?: any; users?: any[] } = {}) {
  const saved: any[] = [];

  const usersRepository: any = {
    findOne: jest.fn(async () => opts.user ?? null),
    find: jest.fn(async () => opts.users ?? []),
    count: jest.fn(async () => 0),
    save: jest.fn(async (u: any) => {
      saved.push(u);
      return u;
    }),
  };

  const bookingsRepository: any = {
    count: jest.fn(async () => 0),
  };

  const favouritesRepository: any = {
    count: jest.fn(async () => 0),
  };

  const service = new UsersService(
    usersRepository,
    bookingsRepository,
    favouritesRepository,
  );
  return {
    service,
    usersRepository,
    bookingsRepository,
    favouritesRepository,
    saved,
  };
}

const user = (over: Partial<any> = {}) => ({
  id: 'user-1',
  name: 'Anu',
  profileImageUrl: null,
  isAvailableForWork: false,
  fcmToken: null,
  isVerified: false,
  hasWorkerProfile: false,
  approvalStatus: UserApprovalStatus.PENDING,
  ...over,
});

describe('UsersService', () => {
  describe('findById', () => {
    it('returns the user when found', async () => {
      const { service } = makeService({ user: user() });
      await expect(service.findById('user-1')).resolves.toMatchObject({
        id: 'user-1',
      });
    });

    it('throws NotFound when missing', async () => {
      const { service } = makeService({ user: null });
      await expect(service.findById('nope')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });
  });

  describe('getUserStats', () => {
    it('returns the customer booking count when the user exists', async () => {
      const { service, bookingsRepository } = makeService({ user: user() });
      bookingsRepository.count.mockResolvedValueOnce(7);
      const stats = await service.getUserStats('user-1');
      expect(stats).toEqual({
        bookingsCount: 7,
        reviewsCount: 0,
        savedCount: 0,
      });
      expect(bookingsRepository.count).toHaveBeenCalledWith({
        where: { customer: { id: 'user-1' } },
      });
    });

    it('sources savedCount from the favourites table, scoped to the user', async () => {
      const { service, favouritesRepository } = makeService({ user: user() });
      favouritesRepository.count.mockResolvedValueOnce(4);
      const stats = await service.getUserStats('user-1');
      expect(stats.savedCount).toBe(4);
      expect(favouritesRepository.count).toHaveBeenCalledWith({
        where: { user: { id: 'user-1' } },
      });
    });

    it('returns all-zeros when the user is missing (no booking count attempted)', async () => {
      const { service, bookingsRepository } = makeService({ user: null });
      const stats = await service.getUserStats('ghost');
      expect(stats).toEqual({
        bookingsCount: 0,
        reviewsCount: 0,
        savedCount: 0,
      });
      expect(bookingsRepository.count).not.toHaveBeenCalled();
    });

    it('swallows a repo error (invalid UUID) into all-zeros', async () => {
      const { service, usersRepository } = makeService({ user: user() });
      usersRepository.findOne.mockRejectedValueOnce(
        new Error('invalid input syntax for uuid'),
      );
      const stats = await service.getUserStats('not-a-uuid');
      expect(stats).toEqual({
        bookingsCount: 0,
        reviewsCount: 0,
        savedCount: 0,
      });
    });
  });

  describe('updateProfile', () => {
    it('throws NotFound when the user is missing', async () => {
      const { service } = makeService({ user: null });
      await expect(
        service.updateProfile('x', { name: 'New' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('applies only the defined fields and leaves undefined ones untouched', async () => {
      const existing = user({ name: 'Old', isAvailableForWork: true });
      const { service, saved } = makeService({ user: existing });
      const result = await service.updateProfile('user-1', { name: 'New' });
      expect(result.name).toBe('New');
      // isAvailableForWork was not in the patch → must remain its prior value
      expect(result.isAvailableForWork).toBe(true);
      expect(saved).toHaveLength(1);
      expect(saved[0].name).toBe('New');
    });

    it('writes profileImageUrl and isAvailableForWork when provided', async () => {
      const { service } = makeService({ user: user() });
      const result = await service.updateProfile('user-1', {
        profileImageUrl: 'http://img/a.png',
        isAvailableForWork: true,
      });
      expect(result.profileImageUrl).toBe('http://img/a.png');
      expect(result.isAvailableForWork).toBe(true);
    });

    it('ignores role/hasWorkerProfile unless allowPrivilegedFields is set', async () => {
      const existing = user({ role: UserRole.CUSTOMER, hasWorkerProfile: false });
      const { service } = makeService({ user: existing });
      const result = await service.updateProfile('user-1', {
        role: UserRole.ADMIN,
        hasWorkerProfile: true,
      });
      expect(result.role).toBe(UserRole.CUSTOMER);
      expect(result.hasWorkerProfile).toBe(false);
    });

    it('persists role/hasWorkerProfile when allowPrivilegedFields is true', async () => {
      const existing = user({ role: UserRole.CUSTOMER });
      const { service } = makeService({ user: existing });
      const result = await service.updateProfile(
        'user-1',
        { role: UserRole.OWNER, hasWorkerProfile: true },
        { allowPrivilegedFields: true },
      );
      expect(result.role).toBe(UserRole.OWNER);
      expect(result.hasWorkerProfile).toBe(true);
    });
  });

  describe('updateFcmToken', () => {
    it('throws NotFound when the user is missing', async () => {
      const { service } = makeService({ user: null });
      await expect(service.updateFcmToken('x', 'tok')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    it('writes the token and saves', async () => {
      const { service, saved } = makeService({ user: user() });
      const result = await service.updateFcmToken('user-1', 'fcm-abc');
      expect(result.fcmToken).toBe('fcm-abc');
      expect(saved[0].fcmToken).toBe('fcm-abc');
    });
  });

  describe('findAll', () => {
    it('returns a paginated list with talent relations', async () => {
      const list = [user({ id: 'a' }), user({ id: 'b' })];
      const { service, usersRepository } = makeService({ users: list });
      await expect(service.findAll(1, 50)).resolves.toHaveLength(2);
      expect(usersRepository.find).toHaveBeenCalledWith({
        order: { createdAt: 'DESC' },
        relations: ['talentProfile', 'talentProfile.professionalSkills'],
        skip: 0,
        take: 50,
      });
    });
  });

  describe('updateApprovalStatus', () => {
    it('APPROVED auto-verifies and enables the worker profile', async () => {
      const { service } = makeService({ user: user() });
      const result = await service.updateApprovalStatus(
        'user-1',
        UserApprovalStatus.APPROVED,
      );
      expect(result.approvalStatus).toBe(UserApprovalStatus.APPROVED);
      expect(result.isVerified).toBe(true);
      expect(result.hasWorkerProfile).toBe(true);
    });

    it('REJECTED clears isVerified', async () => {
      const { service } = makeService({
        user: user({ isVerified: true, hasWorkerProfile: true }),
      });
      const result = await service.updateApprovalStatus(
        'user-1',
        UserApprovalStatus.REJECTED,
      );
      expect(result.approvalStatus).toBe(UserApprovalStatus.REJECTED);
      expect(result.isVerified).toBe(false);
    });

    it('PENDING leaves verification flags unchanged', async () => {
      const { service } = makeService({
        user: user({ isVerified: true, hasWorkerProfile: true }),
      });
      const result = await service.updateApprovalStatus(
        'user-1',
        UserApprovalStatus.PENDING,
      );
      expect(result.approvalStatus).toBe(UserApprovalStatus.PENDING);
      expect(result.isVerified).toBe(true);
      expect(result.hasWorkerProfile).toBe(true);
    });

    it('throws NotFound (via findById) when the user is missing', async () => {
      const { service } = makeService({ user: null });
      await expect(
        service.updateApprovalStatus('x', UserApprovalStatus.APPROVED),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('updateVerification', () => {
    it('true auto-enables hasWorkerProfile', async () => {
      const { service } = makeService({ user: user() });
      const result = await service.updateVerification('user-1', true);
      expect(result.isVerified).toBe(true);
      expect(result.hasWorkerProfile).toBe(true);
    });

    it('false sets isVerified false and leaves hasWorkerProfile alone', async () => {
      const { service } = makeService({
        user: user({ hasWorkerProfile: true }),
      });
      const result = await service.updateVerification('user-1', false);
      expect(result.isVerified).toBe(false);
      expect(result.hasWorkerProfile).toBe(true);
    });

    it('throws NotFound when the user is missing', async () => {
      const { service } = makeService({ user: null });
      await expect(
        service.updateVerification('x', true),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('getSystemSummary', () => {
    it('aggregates the four counts and recent users', async () => {
      const recent = [user({ id: 'r1' }), user({ id: 'r2' })];
      const { service, usersRepository, bookingsRepository } = makeService({
        users: recent,
      });
      usersRepository.count
        .mockResolvedValueOnce(100) // totalUsers
        .mockResolvedValueOnce(40) // totalWorkers
        .mockResolvedValueOnce(3); // pendingApprovals
      bookingsRepository.count.mockResolvedValueOnce(250); // totalBookings

      const summary = await service.getSystemSummary();
      expect(summary).toMatchObject({
        totalUsers: 100,
        totalWorkers: 40,
        totalBookings: 250,
        pendingApprovals: 3,
      });
      expect(summary.recentUsers).toHaveLength(2);
      expect(usersRepository.find).toHaveBeenCalledWith({
        order: { createdAt: 'DESC' },
        take: 5,
      });
    });
  });

  describe('searchUsers', () => {
    it('returns [] for an empty/whitespace query without hitting the DB', async () => {
      const { service, usersRepository } = makeService();
      await expect(service.searchUsers('   ')).resolves.toEqual([]);
      expect(usersRepository.find).not.toHaveBeenCalled();
    });

    it('returns [] for queries shorter than 3 characters', async () => {
      const { service, usersRepository } = makeService();
      await expect(service.searchUsers('ab')).resolves.toEqual([]);
      expect(usersRepository.find).not.toHaveBeenCalled();
    });

    it('returns the matched rows from the repository for a non-empty query', async () => {
      const rows = [
        user({ id: 'u1', name: 'Anu' }),
        user({ id: 'u2', name: 'Anand' }),
      ];
      const { service, usersRepository } = makeService({ users: rows });
      const res = await service.searchUsers('anu');
      expect(res).toEqual(rows);
      expect(usersRepository.find).toHaveBeenCalledTimes(1);
    });

    it('matches name OR phone, projects lean columns, defaults take=20, orders by name', async () => {
      const { service, usersRepository } = makeService();
      await service.searchUsers('555');
      const arg = usersRepository.find.mock.calls[0][0];
      expect(Array.isArray(arg.where)).toBe(true);
      expect(arg.where).toHaveLength(2);
      expect(Object.keys(arg.where[0])).toEqual(['name']);
      expect(Object.keys(arg.where[1])).toEqual(['phoneNumber']);
      expect(arg.select).toEqual([
        'id',
        'name',
        'phoneNumber',
        'role',
        'profileImageUrl',
      ]);
      expect(arg.take).toBe(20);
      expect(arg.order).toEqual({ name: 'ASC' });
    });

    it('caps a huge limit at 50', async () => {
      const { service, usersRepository } = makeService();
      await service.searchUsers('xxx', 9999);
      expect(usersRepository.find.mock.calls[0][0].take).toBe(50);
    });

    it('defaults a zero limit back to 20', async () => {
      const { service, usersRepository } = makeService();
      await service.searchUsers('xxx', 0);
      expect(usersRepository.find.mock.calls[0][0].take).toBe(20);
    });

    it('strips phoneNumber from results unless includePhone is true', async () => {
      const rows = [
        user({ id: 'u1', name: 'Anu', phoneNumber: '+919000000001' }),
      ];
      const { service, usersRepository } = makeService({ users: rows });
      const without = await service.searchUsers('anu');
      expect(without[0]).not.toHaveProperty('phoneNumber');
      usersRepository.find.mockClear();
      usersRepository.find.mockResolvedValueOnce(rows);
      const withPhone = await service.searchUsers('anu', 20, {
        includePhone: true,
      });
      expect(withPhone[0].phoneNumber).toBe('+919000000001');
    });
  });
});
