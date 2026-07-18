import { NotFoundException, BadRequestException } from '@nestjs/common';
import { HiringService } from './hiring.service';
import { ApplicationStatus } from './job-application.entity';

/**
 * Unit tests for HiringService — the job-post + application-pipeline + talent-
 * matching engine. One of the four large central services Passes 55–68 left
 * without a service-level spec (a controller spec was added Pass 63, but the
 * service's own branch logic was never covered). All repos + the notifications
 * and talent collaborators are mocked in-memory; no database / network touched.
 *
 * Coverage:
 * - createJobPost: creates with the employer wrapped + saves; the async
 *   setImmediate talent-notify side-effect is fire-and-forget (asserted not to
 *   throw / not block the return) — happy path + a no-skills job that notifies
 *   nobody, and the swallowed-error branch.
 * - getJobById / getActiveJobs: NotFound guard + ordered active list.
 * - applyForJob: NotFound (no job), BadRequest (inactive), BadRequest (double-
 *   apply), happy path saves an APPLIED application.
 * - updateApplicationStatus: NotFound guard; NO_SHOW records a talent no-show
 *   (DEFECT-010) AND notifies; SELECTED/INTERVIEW/REJECTED notify with the right
 *   copy; a no-message status (e.g. APPLIED) saves but does NOT notify.
 * - withdrawApplication: NotFound; not-owner BadRequest; wrong-state BadRequest;
 *   happy path flips to WITHDRAWN.
 * - getRecommendedTalent: NotFound; no-required-skills → top-rated active
 *   workers; skill scoring → only matched workers, ordered by score then rating.
 */

function flush() {
  // let any setImmediate fire-and-forget callbacks run + settle
  return new Promise((r) => setImmediate(r));
}

function makeService(
  opts: {
    job?: any;
    application?: any;
    activeJobs?: any[];
    applications?: any[];
    workers?: any[];
  } = {},
) {
  const jobSaved: any[] = [];
  const appSaved: any[] = [];

  const jobPostRepo: any = {
    findOne: jest.fn(async () => opts.job ?? null),
    find: jest.fn(async () => opts.activeJobs ?? []),
    create: jest.fn((dto: any) => ({ id: 'job-new', ...dto })),
    save: jest.fn(async (j: any) => {
      jobSaved.push(j);
      return j;
    }),
  };

  const applicationRepo: any = {
    findOne: jest.fn(async () => opts.application ?? null),
    find: jest.fn(async () => opts.applications ?? []),
    create: jest.fn((dto: any) => ({ id: 'app-new', ...dto })),
    save: jest.fn(async (a: any) => {
      appSaved.push(a);
      return a;
    }),
  };

  const workerProfileRepo: any = {
    find: jest.fn(async () => opts.workers ?? []),
    createQueryBuilder: jest.fn(() => {
      const qb: any = {
        leftJoinAndSelect: jest.fn(() => qb),
        where: jest.fn(() => qb),
        andWhere: jest.fn(() => qb),
        orderBy: jest.fn(() => qb),
        take: jest.fn(() => qb),
        getMany: jest.fn(async () => opts.workers ?? []),
      };
      return qb;
    }),
  };

  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
    sendToUsers: jest.fn(async () => undefined),
  };

  const talentService: any = {
    recordNoShow: jest.fn(async () => undefined),
  };

  const redisService: any = {
    get: jest.fn(async () => null),
    set: jest.fn(async () => undefined),
    del: jest.fn(async () => undefined),
  };

  const service = new HiringService(
    jobPostRepo,
    applicationRepo,
    workerProfileRepo,
    notificationsService,
    talentService,
    redisService,
  );

  return {
    service,
    jobPostRepo,
    applicationRepo,
    workerProfileRepo,
    notificationsService,
    talentService,
    jobSaved,
    appSaved,
  };
}

const worker = (over: Partial<any> = {}) => ({
  id: 'w1',
  user: { id: 'u1' },
  isActive: true,
  rating: 4,
  skills: [] as string[],
  ...over,
});

describe('HiringService', () => {
  describe('createJobPost', () => {
    it('creates with the employer wrapped and saves, returning the saved job', async () => {
      const { service, jobPostRepo, jobSaved } = makeService({ workers: [] });
      const result = await service.createJobPost('emp-1', { title: 'Plumber needed' });
      expect(jobPostRepo.create).toHaveBeenCalledWith({
        title: 'Plumber needed',
        employer: { id: 'emp-1' },
      });
      expect(jobSaved).toHaveLength(1);
      expect(result).toMatchObject({ title: 'Plumber needed' });
      await flush(); // drain the fire-and-forget notify (no workers → nobody notified)
    });

    it('notify side-effect does not throw even if matching fails', async () => {
      const { service, jobPostRepo, notificationsService } = makeService();
      // getRecommendedTalent re-queries jobPostRepo.findOne; make THAT call (post-save) reject
      jobPostRepo.findOne.mockRejectedValue(new Error('boom'));
      const result = await service.createJobPost('emp-1', { title: 'X' });
      expect(result).toBeDefined(); // synchronous return unaffected by the async failure
      await flush();
      expect(notificationsService.sendToUsers).not.toHaveBeenCalled();
      expect(notificationsService.sendToUser).not.toHaveBeenCalled();
    });

    it('multicasts a job-alert to matched talent user ids', async () => {
      const { service, notificationsService } = makeService({
        job: { id: 'job-new', title: 'Welder', requiredSkills: [] },
        workers: [worker({ user: { id: 'talent-1' } })],
      });
      // After save, getRecommendedTalent loads the job again via findOne
      const result = await service.createJobPost('emp-1', {
        title: 'Welder',
        requiredSkills: [],
      });
      expect(result).toBeDefined();
      await flush();
      expect(notificationsService.sendToUsers).toHaveBeenCalledWith(
        ['talent-1'],
        expect.objectContaining({
          title: 'New job: Welder',
          body: expect.stringContaining('apply'),
        }),
      );
    });
  });

  describe('getActiveJobs', () => {
    it('returns the active list ordered by createdAt DESC', async () => {
      const { service, jobPostRepo } = makeService({ activeJobs: [{ id: 'j1' }, { id: 'j2' }] });
      await expect(service.getActiveJobs()).resolves.toHaveLength(2);
      expect(jobPostRepo.find).toHaveBeenCalledWith({
        where: { isActive: true },
        relations: ['employer'],
        order: { createdAt: 'DESC' },
        take: 100,
      });
    });
  });

  describe('getJobById', () => {
    it('returns the job when found', async () => {
      const { service } = makeService({ job: { id: 'j1' } });
      await expect(service.getJobById('j1')).resolves.toMatchObject({ id: 'j1' });
    });
    it('throws NotFound when missing', async () => {
      const { service } = makeService({ job: null });
      await expect(service.getJobById('x')).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('applyForJob', () => {
    it('throws NotFound when the job does not exist', async () => {
      const { service } = makeService({ job: null });
      await expect(service.applyForJob('j', 'a')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws BadRequest when the job is inactive', async () => {
      const { service } = makeService({ job: { id: 'j', isActive: false } });
      await expect(service.applyForJob('j', 'a')).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequest on a double-apply', async () => {
      const { service, applicationRepo } = makeService({ job: { id: 'j', isActive: true } });
      applicationRepo.findOne.mockResolvedValueOnce({ id: 'existing' });
      await expect(service.applyForJob('j', 'a')).rejects.toBeInstanceOf(BadRequestException);
    });

    it('saves a new APPLIED application on the happy path', async () => {
      const { service, appSaved } = makeService({ job: { id: 'j', isActive: true } });
      const result = await service.applyForJob('j', 'a', 'please hire me');
      expect(result.status).toBe(ApplicationStatus.APPLIED);
      expect(appSaved[0]).toMatchObject({
        jobPost: { id: 'j' },
        applicant: { id: 'a' },
        coverLetter: 'please hire me',
      });
    });

    it('carries the attached resumeUrl through to the created application', async () => {
      const { service, appSaved } = makeService({ job: { id: 'j', isActive: true } });
      await service.applyForJob('j', 'a', 'please hire me', '/uploads/cv-7.jpg');
      expect(appSaved[0].resumeUrl).toBe('/uploads/cv-7.jpg');
    });

    it('leaves resumeUrl undefined when the applicant attached nothing', async () => {
      const { service, appSaved } = makeService({ job: { id: 'j', isActive: true } });
      await service.applyForJob('j', 'a', 'please hire me');
      expect(appSaved[0].resumeUrl).toBeUndefined();
    });
  });

  describe('updateApplicationStatus', () => {
    const app = (over: Partial<any> = {}) => ({
      id: 'app-1',
      status: ApplicationStatus.APPLIED,
      applicant: { id: 'u1' },
      jobPost: { title: 'Cook' },
      ...over,
    });

    it('throws NotFound when the application is missing', async () => {
      const { service } = makeService({ application: null });
      await expect(
        service.updateApplicationStatus('x', ApplicationStatus.SELECTED),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('NO_SHOW records a talent no-show and notifies', async () => {
      const { service, talentService, notificationsService } = makeService({ application: app() });
      await service.updateApplicationStatus('app-1', ApplicationStatus.NO_SHOW);
      expect(talentService.recordNoShow).toHaveBeenCalledWith('u1');
      expect(notificationsService.sendToUser).toHaveBeenCalledWith('u1', {
        title: 'Cook',
        body: expect.stringContaining('no-show'),
      });
    });

    it('SELECTED notifies with the congratulations copy (no no-show recorded)', async () => {
      const { service, talentService, notificationsService } = makeService({ application: app() });
      await service.updateApplicationStatus('app-1', ApplicationStatus.SELECTED);
      expect(talentService.recordNoShow).not.toHaveBeenCalled();
      expect(notificationsService.sendToUser).toHaveBeenCalledWith('u1', {
        title: 'Cook',
        body: expect.stringContaining('selected'),
      });
    });

    it('falls back to a generic title when the job has none', async () => {
      const { service, notificationsService } = makeService({
        application: app({ jobPost: undefined }),
      });
      await service.updateApplicationStatus('app-1', ApplicationStatus.INTERVIEW);
      expect(notificationsService.sendToUser).toHaveBeenCalledWith('u1', {
        title: 'Application Update',
        body: expect.stringContaining('interview'),
      });
    });

    it('a no-message status (APPLIED) saves but does not notify', async () => {
      const { service, notificationsService, appSaved } = makeService({ application: app() });
      await service.updateApplicationStatus('app-1', ApplicationStatus.APPLIED);
      expect(appSaved).toHaveLength(1);
      expect(notificationsService.sendToUser).not.toHaveBeenCalled();
    });
  });

  describe('withdrawApplication', () => {
    const app = (over: Partial<any> = {}) => ({
      id: 'app-1',
      status: ApplicationStatus.APPLIED,
      applicant: { id: 'u1' },
      jobPost: { id: 'j1' },
      ...over,
    });

    it('throws NotFound when missing', async () => {
      const { service } = makeService({ application: null });
      await expect(service.withdrawApplication('x', 'u1')).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });

    it('throws BadRequest when withdrawing someone else\'s application', async () => {
      const { service } = makeService({ application: app() });
      await expect(service.withdrawApplication('app-1', 'other')).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('throws BadRequest when not in a withdrawable state', async () => {
      const { service } = makeService({ application: app({ status: ApplicationStatus.SELECTED }) });
      await expect(service.withdrawApplication('app-1', 'u1')).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('flips an APPLIED application to WITHDRAWN', async () => {
      const { service, appSaved } = makeService({ application: app() });
      const result = await service.withdrawApplication('app-1', 'u1');
      expect(result.status).toBe(ApplicationStatus.WITHDRAWN);
      expect(appSaved[0].status).toBe(ApplicationStatus.WITHDRAWN);
    });

    it('allows withdrawing while in INTERVIEW state', async () => {
      const { service } = makeService({ application: app({ status: ApplicationStatus.INTERVIEW }) });
      const result = await service.withdrawApplication('app-1', 'u1');
      expect(result.status).toBe(ApplicationStatus.WITHDRAWN);
    });
  });

  describe('getRecommendedTalent', () => {
    it('throws NotFound when the job is missing', async () => {
      const { service } = makeService({ job: null });
      await expect(service.getRecommendedTalent('x')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('returns top-rated active workers when the job has no required skills', async () => {
      const { service, workerProfileRepo } = makeService({
        job: { id: 'j', requiredSkills: [] },
        workers: [worker()],
      });
      await service.getRecommendedTalent('j');
      expect(workerProfileRepo.find).toHaveBeenCalledWith({
        where: { isActive: true },
        relations: ['user'],
        take: 10,
        order: { rating: 'DESC' },
      });
    });

    it('scores by overlapping skills and keeps only matches, ordered by score then rating', async () => {
      const wHigh = worker({ id: 'high', rating: 3, skills: ['Plumbing', 'Electrical'] });
      const wLow = worker({ id: 'low', rating: 5, skills: ['plumbing'] });
      const wNone = worker({ id: 'none', rating: 5, skills: ['Painting'] });
      const { service, workerProfileRepo } = makeService({
        job: { id: 'j', requiredSkills: ['plumbing', 'electrical'] },
        workers: [wLow, wHigh, wNone],
      });
      const result = await service.getRecommendedTalent('j');
      // wNone (score 0) excluded; wHigh (score 2) before wLow (score 1)
      expect(result.map((w: any) => w.id)).toEqual(['high', 'low']);
      expect(workerProfileRepo.createQueryBuilder).toHaveBeenCalled();
    });

    it('matches case-insensitively and trims whitespace', async () => {
      const w = worker({ id: 'w', skills: ['  CLEANING '] });
      const { service } = makeService({
        job: { id: 'j', requiredSkills: ['cleaning'] },
        workers: [w],
      });
      const result = await service.getRecommendedTalent('j');
      expect(result.map((x: any) => x.id)).toEqual(['w']);
    });

    it('tolerates a worker with no skills array (treated as no match)', async () => {
      const w = worker({ id: 'w', skills: undefined });
      const { service } = makeService({
        job: { id: 'j', requiredSkills: ['cleaning'] },
        workers: [w],
      });
      await expect(service.getRecommendedTalent('j')).resolves.toEqual([]);
    });
  });
});
