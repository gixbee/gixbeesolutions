import { HiringController } from './hiring.controller';
import { ApplicationStatus } from './job-application.entity';
import { BadRequestException } from '@nestjs/common';

/**
 * Unit tests for the HiringController HTTP layer — a thin delegation over
 * HiringService. Instantiated directly with a jest-mock service (matching this
 * repo's controller-spec style — no Nest TestingModule, no network). Asserts
 * request→service delegation, the JWT userId source for guarded routes
 * (req.user.userId), URL :id forwarding for public lookups, the createJobPost
 * required-field guard + requiredSkills default, and the updateApplicationStatus
 * enum validation guard.
 */

function makeController() {
  const hiringService: any = {
    createJobPost: jest.fn(async () => ({ id: 'j1' })),
    getActiveJobs: jest.fn(async () => [{ id: 'j1' }]),
    getJobById: jest.fn(async () => ({ id: 'j1' })),
    getRecommendedTalent: jest.fn(async () => [{ id: 't1' }]),
    applyForJob: jest.fn(async () => ({ id: 'a1' })),
    getMyApplications: jest.fn(async () => [{ id: 'a1' }]),
    getApplicationsForJob: jest.fn(async () => [{ id: 'a1' }]),
    withdrawApplication: jest.fn(async () => ({ id: 'a1', status: 'WITHDRAWN' })),
    updateApplicationStatus: jest.fn(async () => ({ id: 'a1', status: 'SELECTED' })),
  };
  const controller = new HiringController(hiringService);
  return { controller, hiringService };
}

describe('HiringController.createJobPost', () => {
  it('forwards the authed userId + a normalized job body (requiredSkills default [])', async () => {
    const { controller, hiringService } = makeController();
    await controller.createJobPost(
      { user: { userId: 'u-1' } },
      { title: 'Cook', description: 'Catering gig', salaryMin: 100, salaryMax: 200 },
    );
    expect(hiringService.createJobPost).toHaveBeenCalledWith('u-1', {
      title: 'Cook',
      description: 'Catering gig',
      requiredSkills: [],
      salaryMin: 100,
      salaryMax: 200,
    });
  });

  it('passes through a provided requiredSkills array', async () => {
    const { controller, hiringService } = makeController();
    await controller.createJobPost(
      { user: { userId: 'u-1' } },
      { title: 'Cook', description: 'gig', requiredSkills: ['baking'] },
    );
    expect(hiringService.createJobPost.mock.calls[0][1].requiredSkills).toEqual(['baking']);
  });

  it('throws BadRequest and never calls the service when title is missing', async () => {
    const { controller, hiringService } = makeController();
    await expect(
      controller.createJobPost({ user: { userId: 'u-1' } }, { title: '', description: 'gig' } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(hiringService.createJobPost).not.toHaveBeenCalled();
  });

  it('throws BadRequest when description is missing', async () => {
    const { controller } = makeController();
    await expect(
      controller.createJobPost({ user: { userId: 'u-1' } }, { title: 'Cook', description: '' } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('HiringController.getActiveJobs', () => {
  it('delegates to getActiveJobs (public)', async () => {
    const { controller, hiringService } = makeController();
    const res = await controller.getActiveJobs();
    expect(hiringService.getActiveJobs).toHaveBeenCalledTimes(1);
    expect(res).toEqual([{ id: 'j1' }]);
  });
});

describe('HiringController.getJobById', () => {
  it('forwards the URL :id', async () => {
    const { controller, hiringService } = makeController();
    await controller.getJobById('j-9');
    expect(hiringService.getJobById).toHaveBeenCalledWith('j-9');
  });
});

describe('HiringController.getTalentMatches', () => {
  it('delegates to getRecommendedTalent with the URL :id and JWT user', async () => {
    const { controller, hiringService } = makeController();
    await controller.getTalentMatches('j-9', { user: { userId: 'emp-1' } });
    expect(hiringService.getRecommendedTalent).toHaveBeenCalledWith(
      'j-9',
      'emp-1',
    );
  });
});

describe('HiringController.applyForJob', () => {
  it('forwards jobId (URL), authed userId, the cover letter, and the resumeUrl', async () => {
    const { controller, hiringService } = makeController();
    await controller.applyForJob('j-9', { user: { userId: 'u-1' } }, {
      coverLetter: 'hi',
      resumeUrl: '/uploads/cv-7.jpg',
    });
    expect(hiringService.applyForJob).toHaveBeenCalledWith('j-9', 'u-1', 'hi', '/uploads/cv-7.jpg');
  });

  it('passes undefined resumeUrl when none is attached', async () => {
    const { controller, hiringService } = makeController();
    await controller.applyForJob('j-9', { user: { userId: 'u-1' } }, { coverLetter: 'hi' });
    expect(hiringService.applyForJob).toHaveBeenCalledWith('j-9', 'u-1', 'hi', undefined);
  });
});

describe('HiringController.getMyApplications', () => {
  it('uses the JWT userId with default pagination', async () => {
    const { controller, hiringService } = makeController();
    await controller.getMyApplications({ user: { userId: 'u-1' } });
    expect(hiringService.getMyApplications).toHaveBeenCalledWith('u-1', 1, 50);
  });
});

describe('HiringController.getApplicationsForJob', () => {
  it('forwards the URL jobId, JWT user, and default pagination', async () => {
    const { controller, hiringService } = makeController();
    await controller.getApplicationsForJob('j-9', {
      user: { userId: 'emp-1' },
    });
    expect(hiringService.getApplicationsForJob).toHaveBeenCalledWith(
      'j-9',
      'emp-1',
      1,
      50,
    );
  });
});

describe('HiringController.withdrawApplication', () => {
  it('forwards the applicationId (URL) + authed userId', async () => {
    const { controller, hiringService } = makeController();
    await controller.withdrawApplication('a-1', { user: { userId: 'u-1' } });
    expect(hiringService.withdrawApplication).toHaveBeenCalledWith('a-1', 'u-1');
  });
});

describe('HiringController.updateApplicationStatus', () => {
  it('forwards applicationId + a valid status', async () => {
    const { controller, hiringService } = makeController();
    await controller.updateApplicationStatus(
      'a-1',
      { user: { userId: 'emp-1' } },
      { status: ApplicationStatus.SELECTED } as any,
    );
    expect(hiringService.updateApplicationStatus).toHaveBeenCalledWith(
      'a-1',
      ApplicationStatus.SELECTED,
      'emp-1',
    );
  });

  it('throws BadRequest and never calls the service for an invalid status', async () => {
    const { controller, hiringService } = makeController();
    await expect(
      controller.updateApplicationStatus(
        'a-1',
        { user: { userId: 'emp-1' } },
        { status: 'NOPE' } as any,
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(hiringService.updateApplicationStatus).not.toHaveBeenCalled();
  });

  it('throws BadRequest when status is missing', async () => {
    const { controller } = makeController();
    await expect(
      controller.updateApplicationStatus(
        'a-1',
        { user: { userId: 'emp-1' } },
        {} as any,
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
