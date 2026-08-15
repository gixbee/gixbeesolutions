import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Brackets, Repository } from 'typeorm';
import { JobPost } from './job-post.entity';
import { JobApplication, ApplicationStatus } from './job-application.entity';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { User } from '../users/user.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { TalentService } from '../talent/talent.service';
import { RedisService } from '../redis/redis.service';
import { stripPrivateFields } from '../common/sanitize';

@Injectable()
export class HiringService {
  // AUDIT FIX: the active-jobs feed hit Postgres on every request (and the
  // matched feed re-read it per user). Cache the shared list for 60s;
  // per-user scoring still runs on the cached array.
  private static readonly JOBS_CACHE_KEY = 'hiring:jobs:active';
  /** Max active jobs kept in the shared Redis/DB feed. */
  private static readonly ACTIVE_JOBS_CAP = 100;
  /** Max workers scanned when skill-matching for a job post. */
  private static readonly RECOMMENDED_SCAN_CAP = 200;
  /** Max candidates returned to the employer UI. */
  private static readonly RECOMMENDED_RETURN_CAP = 20;
  constructor(
    @InjectRepository(JobPost)
    private readonly jobPostRepo: Repository<JobPost>,
    @InjectRepository(JobApplication)
    private readonly applicationRepo: Repository<JobApplication>,
    @InjectRepository(WorkerProfile)
    private readonly workerProfileRepo: Repository<WorkerProfile>,
    private readonly notificationsService: NotificationsService,
    private readonly talentService: TalentService,
    private readonly redisService: RedisService,
  ) {}

  private async invalidateJobsCache(): Promise<void> {
    await this.redisService.del(HiringService.JOBS_CACHE_KEY).catch(() => {});
  }

  // ─── JOB POSTS ─────────────────────────────────────────────────────────

  // DEFECT-005 FIX: Notify matched talent when a new job is posted
  async createJobPost(
    employerId: string,
    data: Partial<JobPost>,
  ): Promise<JobPost> {
    const job = this.jobPostRepo.create({
      ...data,
      employer: { id: employerId } as User,
    });
    const savedJob = await this.jobPostRepo.save(job);
    await this.invalidateJobsCache(); // new post must appear immediately

    // Non-blocking: notify matched talent via FCM multicast (AUDIT FIX:
    // was a serial sendToUser loop).
    setImmediate(async () => {
      try {
        const matched = await this.getRecommendedTalent(savedJob.id);
        const userIds = matched.filter((m) => m.user?.id).map((m) => m.user.id);
        if (userIds.length === 0) return;
        await this.notificationsService.sendToUsers(userIds, {
          title: `New job: ${savedJob.title}`,
          body: `New opportunity — tap to apply`,
        });
      } catch (e) {
        console.error('Talent notification failed:', e);
      }
    });

    return savedJob;
  }

  async getMyJobPosts(employerId: string): Promise<JobPost[]> {
    return this.jobPostRepo.find({
      where: { employer: { id: employerId } },
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }

  async getActiveJobs(): Promise<JobPost[]> {
    const cached = await this.redisService.get(HiringService.JOBS_CACHE_KEY);
    if (cached) return JSON.parse(cached) as JobPost[];

    // AUDIT FIX: hard take — never load every job post into Redis/memory.
    const rows = await this.jobPostRepo.find({
      where: { isActive: true },
      relations: ['employer'],
      order: { createdAt: 'DESC' },
      take: HiringService.ACTIVE_JOBS_CAP,
    });

    // Cached payloads come back as PLAIN objects, which the global
    // ClassSerializerInterceptor can't sanitize — strip the employer's
    // private fields before they ever enter Redis.
    const jobs = stripPrivateFields(rows);
    await this.redisService
      .set(HiringService.JOBS_CACHE_KEY, JSON.stringify(jobs), 60)
      .catch(() => {});
    return jobs;
  }

  /**
   * Preference-matched feed (v126 "create profile · start matching"):
   * scores active jobs against the seeker's TalentProfile —
   *   +2 per preferredRole hit in title/skills, +1 per skill overlap,
   *   +1 salary fit (expectedSalary within/below the job's range).
   * LENIENT by design: an empty profile returns everything (recency order);
   * scored matches sort first, ties by recency. Never hides all jobs.
   */
  async getMatchedJobs(userId: string): Promise<JobPost[]> {
    const jobs = await this.getActiveJobs();
    let profile: any = null;
    try {
      profile = await this.talentService.getProfile(userId);
    } catch (e) {
      return jobs; // no profile — plain feed
    }

    const roles = ((profile?.preferredRoles ?? []) as string[]).map((r) =>
      r.toLowerCase(),
    );
    const skills = ((profile?.skills ?? []) as string[]).map((s) =>
      s.toLowerCase(),
    );
    const locations = ((profile?.preferredLocations ?? []) as string[]).map(
      (l) => l.toLowerCase(),
    );
    const expectedSalary = profile?.expectedSalary as number | null;

    if (
      roles.length === 0 &&
      skills.length === 0 &&
      locations.length === 0 &&
      !expectedSalary
    ) {
      return jobs;
    }

    const scored = jobs.map((job) => {
      const haystack = [job.title ?? '', ...(job.requiredSkills ?? [])]
        .join(' ')
        .toLowerCase();

      let score = 0;
      for (const role of roles) {
        if (role && haystack.includes(role)) score += 2;
      }
      for (const skill of skills) {
        if (skill && haystack.includes(skill)) score += 1;
      }
      if (expectedSalary) {
        const min = job.salaryMin == null ? null : Number(job.salaryMin);
        const max = job.salaryMax == null ? null : Number(job.salaryMax);
        if (min == null && max == null) {
          // No salary info — neutral.
        } else if ((max ?? min ?? 0) >= expectedSalary) {
          score += 1;
        }
      }
      // Preferred-city hit (uses the newly persisted job.location).
      const jobLoc = (job.location ?? '').toLowerCase();
      if (
        jobLoc &&
        locations.some((l) => l && (jobLoc.includes(l) || l.includes(jobLoc)))
      ) {
        score += 2;
      }
      return { job, score };
    });

    scored.sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return (
        new Date(b.job.createdAt).getTime() -
        new Date(a.job.createdAt).getTime()
      );
    });
    return scored.map((s) => s.job);
  }

  async getJobById(id: string): Promise<JobPost> {
    const job = await this.jobPostRepo.findOne({
      where: { id },
      relations: ['employer'],
    });
    if (!job) throw new NotFoundException('Job post not found');
    return job;
  }

  // ─── APPLICATIONS PIPELINE ──────────────────────────────────────────────

  async applyForJob(
    jobId: string,
    applicantId: string,
    coverLetter?: string,
    resumeUrl?: string,
  ): Promise<JobApplication> {
    const job = await this.jobPostRepo.findOne({ where: { id: jobId } });
    if (!job) throw new NotFoundException('Job post not found');
    if (!job.isActive)
      throw new BadRequestException('This job is no longer active');

    // Prevent double applying
    const existing = await this.applicationRepo.findOne({
      where: { jobPost: { id: jobId }, applicant: { id: applicantId } },
    });
    if (existing)
      throw new BadRequestException('You have already applied for this job');

    const app = this.applicationRepo.create({
      jobPost: { id: jobId } as JobPost,
      applicant: { id: applicantId } as User,
      coverLetter,
      resumeUrl,
      status: ApplicationStatus.APPLIED,
    });

    return this.applicationRepo.save(app);
  }

  // DEFECT-009 FIX: Send push notification when application status changes
  // DEFECT-010 FIX: Record no-show when status is NO_SHOW
  async updateApplicationStatus(
    applicationId: string,
    newStatus: ApplicationStatus,
    requesterId: string,
  ): Promise<JobApplication> {
    const app = await this.applicationRepo.findOne({
      where: { id: applicationId },
      relations: ['jobPost', 'jobPost.employer', 'applicant'],
    });

    if (!app) throw new NotFoundException('Application not found');
    // SECURITY FIX: only the job's employer may move an application through
    // the pipeline (was unauthenticated → anyone could SELECT/REJECT/NO_SHOW).
    if (app.jobPost?.employer?.id !== requesterId) {
      throw new ForbiddenException(
        'Only the job owner can update this application',
      );
    }

    app.status = newStatus;
    await this.applicationRepo.save(app);

    // DEFECT-010: Handle no-show penalty
    if (newStatus === ApplicationStatus.NO_SHOW && app.applicant?.id) {
      await this.talentService.recordNoShow(app.applicant.id);
    }

    // DEFECT-009: Send push notification to applicant
    const messages: Partial<Record<ApplicationStatus, string>> = {
      [ApplicationStatus.INTERVIEW]:
        'You have been shortlisted for an interview!',
      [ApplicationStatus.SELECTED]: 'Congratulations! You have been selected.',
      [ApplicationStatus.REJECTED]:
        'Your application was not selected this time.',
      [ApplicationStatus.NO_SHOW]:
        'You were marked as no-show. This affects your ranking.',
    };

    const msg = messages[newStatus];
    if (msg && app.applicant?.id) {
      await this.notificationsService.sendToUser(app.applicant.id, {
        title: app.jobPost?.title || 'Application Update',
        body: msg,
      });
    }

    return app;
  }

  async getApplicationsForJob(
    jobId: string,
    requesterId: string,
    page = 1,
    limit = 50,
  ): Promise<JobApplication[]> {
    // SECURITY FIX: applicant PII (resume, cover letter) is employer-only.
    const job = await this.jobPostRepo.findOne({
      where: { id: jobId },
      relations: ['employer'],
    });
    if (!job) throw new NotFoundException('Job post not found');
    if (job.employer?.id !== requesterId) {
      throw new ForbiddenException('Only the job owner can view applicants');
    }
    return this.applicationRepo.find({
      where: { jobPost: { id: jobId } },
      relations: ['applicant'],
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
  }

  /// Talent withdraws their own application (only while still in play).
  async withdrawApplication(
    applicationId: string,
    applicantId: string,
  ): Promise<JobApplication> {
    const app = await this.applicationRepo.findOne({
      where: { id: applicationId },
      relations: ['jobPost', 'applicant'],
    });
    if (!app) throw new NotFoundException('Application not found');
    if (app.applicant?.id !== applicantId) {
      throw new BadRequestException(
        'You can only withdraw your own application',
      );
    }
    if (
      app.status !== ApplicationStatus.APPLIED &&
      app.status !== ApplicationStatus.INTERVIEW
    ) {
      throw new BadRequestException(
        `Cannot withdraw an application in ${app.status} state`,
      );
    }
    app.status = ApplicationStatus.WITHDRAWN;
    return this.applicationRepo.save(app);
  }

  async getMyApplications(
    userId: string,
    page = 1,
    limit = 50,
  ): Promise<JobApplication[]> {
    return this.applicationRepo.find({
      where: { applicant: { id: userId } },
      relations: ['jobPost', 'jobPost.employer'],
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
  }

  // ─── TALENT MATCHING ────────────────────────────────────────────────────

  async getRecommendedTalent(
    jobId: string,
    requesterId?: string,
  ): Promise<WorkerProfile[]> {
    const job = await this.jobPostRepo.findOne({
      where: { id: jobId },
      relations: ['employer'],
    });
    if (!job) throw new NotFoundException('Job post not found');
    // SECURITY FIX: candidate suggestions are employer-only.
    if (requesterId && job.employer?.id !== requesterId) {
      throw new ForbiddenException('Only the job owner can view matches');
    }

    const requiredSkills = job.requiredSkills;

    if (!requiredSkills || requiredSkills.length === 0) {
      return this.workerProfileRepo.find({
        where: { isActive: true },
        relations: ['user'],
        take: 10,
        order: { rating: 'DESC' },
      });
    }

    // AUDIT FIX: do not load ALL active workers. Pre-filter by skill text
    // (simple-array column) and cap the scan, then score + return a short list.
    const qb = this.workerProfileRepo
      .createQueryBuilder('worker')
      .leftJoinAndSelect('worker.user', 'user')
      .where('worker.isActive = :active', { active: true })
      .andWhere(
        new Brackets((b) => {
          requiredSkills.forEach((skill, i) => {
            const normalized = skill.toLowerCase().trim();
            if (!normalized) return;
            b.orWhere(`LOWER(worker.skills) LIKE :skill${i}`, {
              [`skill${i}`]: `%${normalized}%`,
            });
          });
        }),
      )
      .orderBy('worker.rating', 'DESC')
      .take(HiringService.RECOMMENDED_SCAN_CAP);

    const candidates = await qb.getMany();

    const scoredWorkers = candidates.map((worker) => {
      let score = 0;
      const workerSkills = worker.skills || [];

      const normalizedWorkerSkills = workerSkills.map((s) =>
        s.toLowerCase().trim(),
      );
      const normalizedReqSkills = requiredSkills.map((s) =>
        s.toLowerCase().trim(),
      );

      normalizedReqSkills.forEach((req) => {
        if (normalizedWorkerSkills.includes(req)) score++;
      });

      return { worker, score };
    });

    return scoredWorkers
      .filter((sw) => sw.score > 0)
      .sort((a, b) => b.score - a.score || b.worker.rating - a.worker.rating)
      .slice(0, HiringService.RECOMMENDED_RETURN_CAP)
      .map((sw) => sw.worker);
  }
}
