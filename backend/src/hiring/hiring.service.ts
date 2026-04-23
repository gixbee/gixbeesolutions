import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { JobPost } from './job-post.entity';
import { JobApplication, ApplicationStatus } from './job-application.entity';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { User } from '../users/user.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { TalentService } from '../talent/talent.service';

@Injectable()
export class HiringService {
  constructor(
    @InjectRepository(JobPost)
    private readonly jobPostRepo: Repository<JobPost>,
    @InjectRepository(JobApplication)
    private readonly applicationRepo: Repository<JobApplication>,
    @InjectRepository(WorkerProfile)
    private readonly workerProfileRepo: Repository<WorkerProfile>,
    private readonly notificationsService: NotificationsService,
    private readonly talentService: TalentService,
  ) {}

  // ─── JOB POSTS ─────────────────────────────────────────────────────────

  // DEFECT-005 FIX: Notify matched talent when a new job is posted
  async createJobPost(employerId: string, data: Partial<JobPost>): Promise<JobPost> {
    const job = this.jobPostRepo.create({
      ...data,
      employer: { id: employerId } as User,
    });
    const savedJob = await this.jobPostRepo.save(job);

    // Non-blocking: notify matched talent via OneSignal
    setImmediate(async () => {
      try {
        const matched = await this.getRecommendedTalent(savedJob.id);
        const userIds = matched
          .filter(m => m.user?.id)
          .map(m => m.user.id);
        
        for (const userId of userIds) {
          await this.notificationsService.sendToUser(userId, {
            title: `New job: ${savedJob.title}`,
            body: `New opportunity — tap to apply`,
          });
        }
      } catch (e) {
        console.error('Talent notification failed:', e);
      }
    });

    return savedJob;
  }

  async getActiveJobs(): Promise<JobPost[]> {
    return this.jobPostRepo.find({
      where: { isActive: true },
      relations: ['employer'],
      order: { createdAt: 'DESC' },
    });
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

  async applyForJob(jobId: string, applicantId: string, coverLetter?: string): Promise<JobApplication> {
    const job = await this.jobPostRepo.findOne({ where: { id: jobId } });
    if (!job) throw new NotFoundException('Job post not found');
    if (!job.isActive) throw new BadRequestException('This job is no longer active');

    // Prevent double applying
    const existing = await this.applicationRepo.findOne({
      where: { jobPost: { id: jobId }, applicant: { id: applicantId } },
    });
    if (existing) throw new BadRequestException('You have already applied for this job');

    const app = this.applicationRepo.create({
      jobPost: { id: jobId } as JobPost,
      applicant: { id: applicantId } as User,
      coverLetter,
      status: ApplicationStatus.APPLIED,
    });

    return this.applicationRepo.save(app);
  }

  // DEFECT-009 FIX: Send push notification when application status changes
  // DEFECT-010 FIX: Record no-show when status is NO_SHOW
  async updateApplicationStatus(applicationId: string, newStatus: ApplicationStatus): Promise<JobApplication> {
    const app = await this.applicationRepo.findOne({
      where: { id: applicationId },
      relations: ['jobPost', 'applicant'],
    });

    if (!app) throw new NotFoundException('Application not found');

    app.status = newStatus;
    await this.applicationRepo.save(app);

    // DEFECT-010: Handle no-show penalty
    if (newStatus === ApplicationStatus.NO_SHOW && app.applicant?.id) {
      await this.talentService.recordNoShow(app.applicant.id);
    }

    // DEFECT-009: Send push notification to applicant
    const messages: Partial<Record<ApplicationStatus, string>> = {
      [ApplicationStatus.INTERVIEW]: 'You have been shortlisted for an interview!',
      [ApplicationStatus.SELECTED]: 'Congratulations! You have been selected.',
      [ApplicationStatus.REJECTED]: 'Your application was not selected this time.',
      [ApplicationStatus.NO_SHOW]: 'You were marked as no-show. This affects your ranking.',
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

  async getApplicationsForJob(jobId: string): Promise<JobApplication[]> {
    return this.applicationRepo.find({
      where: { jobPost: { id: jobId } },
      relations: ['applicant'],
      order: { createdAt: 'DESC' },
    });
  }

  async getMyApplications(userId: string): Promise<JobApplication[]> {
    return this.applicationRepo.find({
      where: { applicant: { id: userId } },
      relations: ['jobPost', 'jobPost.employer'],
      order: { createdAt: 'DESC' },
    });
  }

  // ─── TALENT MATCHING ────────────────────────────────────────────────────

  async getRecommendedTalent(jobId: string): Promise<WorkerProfile[]> {
    const job = await this.jobPostRepo.findOne({ where: { id: jobId } });
    if (!job) throw new NotFoundException('Job post not found');

    const requiredSkills = job.requiredSkills;

    if (!requiredSkills || requiredSkills.length === 0) {
      return this.workerProfileRepo.find({
        where: { isActive: true },
        relations: ['user'],
        take: 10,
        order: { rating: 'DESC' },
      });
    }

    const allActiveWorkers = await this.workerProfileRepo.find({
      where: { isActive: true },
      relations: ['user'],
    });

    const scoredWorkers = allActiveWorkers.map(worker => {
      let score = 0;
      const workerSkills = worker.skills || [];
      
      const normalizedWorkerSkills = workerSkills.map(s => s.toLowerCase().trim());
      const normalizedReqSkills = requiredSkills.map(s => s.toLowerCase().trim());

      normalizedReqSkills.forEach(req => {
        if (normalizedWorkerSkills.includes(req)) score++;
      });

      return { worker, score };
    });

    const matched = scoredWorkers
      .filter(sw => sw.score > 0)
      .sort((a, b) => b.score - a.score || b.worker.rating - a.worker.rating)
      .map(sw => sw.worker);

    return matched;
  }
}
