import { BadRequestException, NotFoundException } from '@nestjs/common';
import { HiringService } from './hiring.service';
import { ApplicationStatus } from './job-application.entity';

/**
 * Unit tests for the talent-side application withdrawal policy
 * (POST /hiring/applications/:id/withdraw):
 * - only the applicant themselves may withdraw,
 * - only while the application is still in play (APPLIED / INTERVIEW),
 * - terminal states (SELECTED / REJECTED / NO_SHOW / WITHDRAWN) refuse.
 */
function makeService(applications: Record<string, any>) {
  const saved: any[] = [];
  const applicationRepo: any = {
    findOne: jest.fn(async ({ where: { id } }: any) => applications[id] ?? null),
    save: jest.fn(async (app: any) => {
      saved.push({ ...app });
      return app;
    }),
    create: jest.fn((dto: any) => dto),
    find: jest.fn(async () => []),
  };
  const jobPostRepo: any = { findOne: jest.fn(), find: jest.fn() };
  const workerProfileRepo: any = { find: jest.fn() };
  const notificationsService: any = { sendToUser: jest.fn() };
  const talentService: any = { recordNoShow: jest.fn() };

  const service = new HiringService(
    jobPostRepo,
    applicationRepo,
    workerProfileRepo,
    notificationsService,
    talentService,
  );
  return { service, applicationRepo, saved };
}

const app = (id: string, applicantId: string, status: ApplicationStatus) => ({
  id,
  status,
  applicant: { id: applicantId },
  jobPost: { id: 'job-1', title: 'Electrician needed' },
});

describe('HiringService.withdrawApplication', () => {
  it('withdraws an APPLIED application and persists WITHDRAWN', async () => {
    const a = app('a1', 'talent-1', ApplicationStatus.APPLIED);
    const { service, saved } = makeService({ a1: a });

    const result = await service.withdrawApplication('a1', 'talent-1');

    expect(result.status).toBe(ApplicationStatus.WITHDRAWN);
    expect(saved).toHaveLength(1);
    expect(saved[0].status).toBe(ApplicationStatus.WITHDRAWN);
  });

  it('withdraws an application that is already at INTERVIEW stage', async () => {
    const a = app('a1', 'talent-1', ApplicationStatus.INTERVIEW);
    const { service } = makeService({ a1: a });

    const result = await service.withdrawApplication('a1', 'talent-1');

    expect(result.status).toBe(ApplicationStatus.WITHDRAWN);
  });

  it('throws NotFound for an unknown application id', async () => {
    const { service } = makeService({});

    await expect(
      service.withdrawApplication('nope', 'talent-1'),
    ).rejects.toThrow(NotFoundException);
  });

  it("refuses to withdraw someone else's application and saves nothing", async () => {
    const a = app('a1', 'talent-1', ApplicationStatus.APPLIED);
    const { service, saved } = makeService({ a1: a });

    await expect(
      service.withdrawApplication('a1', 'talent-2'),
    ).rejects.toThrow(BadRequestException);
    expect(saved).toHaveLength(0);
    expect(a.status).toBe(ApplicationStatus.APPLIED);
  });

  it.each([
    ApplicationStatus.SELECTED,
    ApplicationStatus.REJECTED,
    ApplicationStatus.NO_SHOW,
    ApplicationStatus.WITHDRAWN,
  ])('refuses to withdraw an application in %s state', async (status) => {
    const a = app('a1', 'talent-1', status);
    const { service, saved } = makeService({ a1: a });

    await expect(
      service.withdrawApplication('a1', 'talent-1'),
    ).rejects.toThrow(BadRequestException);
    expect(saved).toHaveLength(0);
    expect(a.status).toBe(status);
  });
});
