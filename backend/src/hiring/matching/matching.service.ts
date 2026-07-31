import {
  Injectable,
  BadRequestException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { InjectQueue } from '@nestjs/bull';
import type { Queue } from 'bull';
import { JobPreference, NoticePeriod } from './job-preference.entity';
import { HiringRequest, HiringRequestStatus } from './hiring-request.entity';
import {
  HiringInterest,
  CandidateResponse,
  EmployerDecision,
} from './hiring-interest.entity';
import { User } from '../../users/user.entity';
import { WalletsService } from '../../wallets/wallets.service';
import { NotificationsService } from '../../notifications/notifications.service';

// ── Business constants (FRD + pricing doc) ─────────────────────────────────
export const FREE_PREFERENCES = 2;
export const EXTRA_PREFERENCE_FEE = 50; // ₹/month per extra Job Type
export const PREFERENCE_DELETE_LOCK_DAYS = 7;
export const TARGET_MULTIPLIER = 3; // interested target ≈ 3× vacancies
export const GUARANTEE_WINDOW_HOURS = 24;
/** Batch sizes for the staged fan-out (Hour 0 / 8 / 18 per the pricing doc). */
export const BATCH_SIZES = [40, 20, 10];
export const BATCH_DELAYS_MS = [0, 8 * 3600_000, 18 * 3600_000];

/** ₹ fee tiers by vacancy count (24 Hour Hiring Guarantee doc). */
export function feeForVacancies(v: number): number {
  if (v <= 1) return 49;
  if (v <= 5) return 99;
  if (v <= 10) return 199;
  if (v <= 25) return 399;
  throw new BadRequestException('Maximum 25 vacancies per hiring request');
}

@Injectable()
export class MatchingService {
  private readonly logger = new Logger(MatchingService.name);

  constructor(
    @InjectRepository(JobPreference)
    private readonly prefRepo: Repository<JobPreference>,
    @InjectRepository(HiringRequest)
    private readonly requestRepo: Repository<HiringRequest>,
    @InjectRepository(HiringInterest)
    private readonly interestRepo: Repository<HiringInterest>,
    private readonly walletsService: WalletsService,
    private readonly notificationsService: NotificationsService,
    @InjectQueue('hiring') private readonly hiringQueue: Queue,
  ) {}

  // ══════════════════════════════════════════════════════════════════════
  // CANDIDATE — Job Type preference profiles
  // ══════════════════════════════════════════════════════════════════════

  async listMyPreferences(userId: string): Promise<JobPreference[]> {
    return this.prefRepo.find({
      where: { user: { id: userId }, isActive: true },
      order: { createdAt: 'ASC' },
    });
  }

  async createPreference(
    userId: string,
    dto: {
      jobType: string;
      skills?: string[];
      preferredLocation?: string;
      expectedSalary?: number;
      experienceYears?: number;
      noticePeriod?: NoticePeriod;
    },
  ): Promise<JobPreference> {
    const jobType = (dto.jobType || '').trim();
    if (!jobType) throw new BadRequestException('jobType is required');

    const existing = await this.listMyPreferences(userId);
    if (
      existing.some((p) => p.jobType.toLowerCase() === jobType.toLowerCase())
    ) {
      throw new BadRequestException(
        'You already have a profile for this Job Type',
      );
    }

    // First 2 are free; each extra slot is ₹50/month, wallet-charged now.
    const needsPayment = existing.length >= FREE_PREFERENCES;
    if (needsPayment) {
      await this.walletsService.charge(
        userId,
        EXTRA_PREFERENCE_FEE,
        `Smart Hiring — extra Job Type "${jobType}" (₹${EXTRA_PREFERENCE_FEE}/month)`,
      );
    }

    const pref = this.prefRepo.create({
      user: { id: userId } as User,
      jobType,
      skills: (dto.skills ?? []).map((s) => s.trim()).filter(Boolean),
      preferredLocation: dto.preferredLocation?.trim(),
      expectedSalary: dto.expectedSalary ?? 0,
      experienceYears: Math.max(0, Math.round(dto.experienceYears ?? 0)),
      noticePeriod: dto.noticePeriod ?? NoticePeriod.IMMEDIATE,
      isPaid: needsPayment,
      paidUntil: needsPayment
        ? new Date(Date.now() + 30 * 24 * 3600_000)
        : null,
    });
    return this.prefRepo.save(pref);
  }

  /** FRD rule: everything editable EXCEPT jobType. */
  async updatePreference(
    userId: string,
    prefId: string,
    dto: Partial<{
      jobType: string;
      skills: string[];
      preferredLocation: string;
      expectedSalary: number;
      experienceYears: number;
      noticePeriod: NoticePeriod;
    }>,
  ): Promise<JobPreference> {
    const pref = await this.prefRepo.findOne({
      where: { id: prefId, user: { id: userId }, isActive: true },
    });
    if (!pref) throw new NotFoundException('Job Type profile not found');
    if (
      dto.jobType &&
      dto.jobType.trim().toLowerCase() !== pref.jobType.toLowerCase()
    ) {
      throw new BadRequestException(
        'Job Type cannot be changed after creation. Delete this profile (after 7 days) and create a new one.',
      );
    }
    if (dto.skills !== undefined) {
      pref.skills = dto.skills.map((s) => s.trim()).filter(Boolean);
    }
    if (dto.preferredLocation !== undefined) {
      pref.preferredLocation = dto.preferredLocation.trim();
    }
    if (dto.expectedSalary !== undefined) {
      pref.expectedSalary = dto.expectedSalary;
    }
    if (dto.experienceYears !== undefined) {
      pref.experienceYears = Math.max(0, Math.round(dto.experienceYears));
    }
    if (dto.noticePeriod !== undefined) pref.noticePeriod = dto.noticePeriod;
    return this.prefRepo.save(pref);
  }

  /** FRD rule: deletable only after 7 days (soft delete). */
  async deletePreference(userId: string, prefId: string): Promise<void> {
    const pref = await this.prefRepo.findOne({
      where: { id: prefId, user: { id: userId }, isActive: true },
    });
    if (!pref) throw new NotFoundException('Job Type profile not found');
    const ageMs = Date.now() - new Date(pref.createdAt).getTime();
    const lockMs = PREFERENCE_DELETE_LOCK_DAYS * 24 * 3600_000;
    if (ageMs < lockMs) {
      const daysLeft = Math.ceil((lockMs - ageMs) / (24 * 3600_000));
      throw new BadRequestException(
        `Job Type profiles can be deleted only after ${PREFERENCE_DELETE_LOCK_DAYS} days — ${daysLeft} day(s) remaining.`,
      );
    }
    pref.isActive = false;
    await this.prefRepo.save(pref);
  }

  // ══════════════════════════════════════════════════════════════════════
  // MATCHING — shared candidate query
  // ══════════════════════════════════════════════════════════════════════

  /**
   * Core matcher (FRD): jobType equality, expected salary within the offer,
   * location overlap, minimum experience, ≥1 skill overlap when both sides
   * declared skills. Notice period is delivered to the employer as data
   * rather than used as a hard filter — Indian hiring rarely rejects a good
   * candidate purely on 30-day notice.
   */
  private async findMatchingPreferences(criteria: {
    jobType: string;
    salaryOffered: number;
    location?: string;
    experienceMinYears?: number;
    skills?: string[];
    excludeUserIds?: string[];
    limit?: number;
  }): Promise<JobPreference[]> {
    const qb = this.prefRepo
      .createQueryBuilder('pref')
      .leftJoinAndSelect('pref.user', 'user')
      .where('pref.isActive = true')
      .andWhere('LOWER(pref.jobType) = LOWER(:jobType)', {
        jobType: criteria.jobType.trim(),
      })
      .andWhere('pref.expectedSalary <= :salary', {
        salary: criteria.salaryOffered,
      })
      .andWhere('pref.experienceYears >= :minExp', {
        minExp: criteria.experienceMinYears ?? 0,
      });

    if (criteria.location?.trim()) {
      qb.andWhere('LOWER(pref.preferredLocation) LIKE :loc', {
        loc: `%${criteria.location.trim().toLowerCase()}%`,
      });
    }
    if (criteria.excludeUserIds?.length) {
      qb.andWhere('user.id NOT IN (:...excluded)', {
        excluded: criteria.excludeUserIds,
      });
    }

    qb.orderBy('pref.createdAt', 'ASC').take(criteria.limit ?? 200);
    const prefs = await qb.getMany();

    // Skill overlap in memory (simple-array column). Lenient by design:
    // candidates with no skills listed still match — same philosophy as the
    // Instant Help language filter.
    const wanted = (criteria.skills ?? [])
      .map((s) => s.trim().toLowerCase())
      .filter(Boolean);
    if (wanted.length === 0) return prefs;
    return prefs.filter((p) => {
      const have = (p.skills ?? []).map((s) => s.toLowerCase());
      return have.length === 0 || have.some((s) => wanted.includes(s));
    });
  }

  /** Salary-slider live estimate for the employer form. Approximate. */
  async estimateCandidates(criteria: {
    jobType: string;
    salaryOffered: number;
    location?: string;
    experienceMinYears?: number;
    skills?: string[];
  }): Promise<{ estimated: number }> {
    if (!criteria.jobType?.trim()) return { estimated: 0 };
    const matches = await this.findMatchingPreferences(criteria);
    return { estimated: matches.length };
  }

  // ══════════════════════════════════════════════════════════════════════
  // EMPLOYER — hiring requests + 24 h guarantee
  // ══════════════════════════════════════════════════════════════════════

  async createRequest(
    employerId: string,
    dto: {
      jobType: string;
      skills?: string[];
      location?: string;
      salaryOffered: number;
      experienceMinYears?: number;
      vacancies: number;
    },
  ): Promise<{ request: HiringRequest; estimatedCandidates: number }> {
    const jobType = (dto.jobType || '').trim();
    if (!jobType) throw new BadRequestException('jobType is required');
    const vacancies = Math.max(1, Math.round(dto.vacancies || 1));
    const fee = feeForVacancies(vacancies);
    if (!(dto.salaryOffered > 0)) {
      throw new BadRequestException('salaryOffered (₹/month) is required');
    }

    // Charge the wallet FIRST (employers pay for matching, not posting).
    await this.walletsService.charge(
      employerId,
      fee,
      `Smart Hiring — ${jobType} × ${vacancies} vacanc${vacancies > 1 ? 'ies' : 'y'} (24 h guarantee)`,
    );

    const request = await this.requestRepo.save(
      this.requestRepo.create({
        employer: { id: employerId } as User,
        jobType,
        skills: (dto.skills ?? []).map((s) => s.trim()).filter(Boolean),
        location: dto.location?.trim(),
        salaryOffered: dto.salaryOffered,
        experienceMinYears: Math.max(
          0,
          Math.round(dto.experienceMinYears ?? 0),
        ),
        vacancies,
        targetInterested: vacancies * TARGET_MULTIPLIER,
        feeAmount: fee,
        status: HiringRequestStatus.COLLECTING,
        deadlineAt: new Date(Date.now() + GUARANTEE_WINDOW_HOURS * 3600_000),
      }),
    );

    // Staged fan-out (Hour 0 / 8 / 18) + finalize at the 24 h deadline.
    // Bull jobIds make re-scheduling idempotent across restarts/replicas.
    for (let i = 0; i < BATCH_DELAYS_MS.length; i++) {
      await this.hiringQueue.add(
        'batch',
        { requestId: request.id, batchIndex: i },
        {
          jobId: `hiring:batch:${request.id}:${i}`,
          delay: BATCH_DELAYS_MS[i],
          removeOnComplete: true,
          removeOnFail: 25,
        },
      );
    }
    await this.hiringQueue.add(
      'finalize',
      { requestId: request.id },
      {
        jobId: `hiring:finalize:${request.id}`,
        delay: GUARANTEE_WINDOW_HOURS * 3600_000,
        removeOnComplete: true,
        removeOnFail: 25,
      },
    );

    const { estimated } = await this.estimateCandidates({
      jobType,
      salaryOffered: dto.salaryOffered,
      location: dto.location,
      experienceMinYears: dto.experienceMinYears,
      skills: dto.skills,
    });
    return { request, estimatedCandidates: estimated };
  }

  /** Processor entry: send one notification batch to fresh matches. */
  async sendBatch(requestId: string, batchIndex: number): Promise<void> {
    const request = await this.requestRepo.findOne({
      where: { id: requestId },
      relations: ['employer'],
    });
    if (!request || request.status !== HiringRequestStatus.COLLECTING) return;

    // Skip further batches once the target is already met.
    const interested = await this.countInterested(requestId);
    if (interested >= request.targetInterested) return;

    const alreadyNotified = await this.interestRepo.find({
      where: { request: { id: requestId } },
      relations: ['candidate'],
    });
    const excludeUserIds = [
      request.employer.id,
      ...alreadyNotified.map((i) => i.candidate.id),
    ];

    const batchSize = BATCH_SIZES[Math.min(batchIndex, BATCH_SIZES.length - 1)];
    const matches = await this.findMatchingPreferences({
      jobType: request.jobType,
      salaryOffered: Number(request.salaryOffered),
      location: request.location,
      experienceMinYears: request.experienceMinYears,
      skills: request.skills,
      excludeUserIds,
      limit: batchSize,
    });
    if (matches.length === 0) {
      this.logger.log(
        `[Hiring ${requestId}] batch ${batchIndex}: no fresh matches`,
      );
      return;
    }

    const now = new Date();
    await this.interestRepo.save(
      matches.map((pref) =>
        this.interestRepo.create({
          request: { id: requestId } as HiringRequest,
          candidate: { id: pref.user.id } as User,
          preference: { id: pref.id } as JobPreference,
          response: CandidateResponse.PENDING,
          notifiedAt: now,
        }),
      ),
    );

    request.batchesSent += 1;
    await this.requestRepo.save(request);

    const salary = Math.round(Number(request.salaryOffered));
    await this.notificationsService
      .sendToUsers(
        matches.map((p) => p.user.id),
        {
          title: `New ${request.jobType} opening`,
          body: `₹${salary}/month · ${request.location || 'your area'} — tap Interested if you want this job.`,
          data: {
            type: 'hiring_offer',
            requestId,
            jobType: request.jobType,
            salary: String(salary),
            location: request.location ?? '',
          },
        },
      )
      .catch((e) =>
        this.logger.error(`[Hiring ${requestId}] batch FCM failed: ${e}`),
      );

    this.logger.log(
      `[Hiring ${requestId}] batch ${batchIndex}: notified ${matches.length} candidates`,
    );
  }

  private async countInterested(requestId: string): Promise<number> {
    return this.interestRepo.count({
      where: {
        request: { id: requestId },
        response: CandidateResponse.INTERESTED,
      },
    });
  }

  /** Processor entry: 24 h deadline — deliver or trip the guarantee. */
  async finalize(requestId: string): Promise<void> {
    const request = await this.requestRepo.findOne({
      where: { id: requestId },
      relations: ['employer'],
    });
    if (!request || request.status !== HiringRequestStatus.COLLECTING) return;

    const interested = await this.countInterested(requestId);
    // Guaranteed minimum: at least one interested candidate per vacancy.
    if (interested >= request.vacancies) {
      await this.deliver(request, interested);
      return;
    }

    request.status = HiringRequestStatus.GUARANTEE_FAILED;
    await this.requestRepo.save(request);
    await this.notificationsService
      .sendToUser(request.employer.id, {
        title: 'Hiring guarantee — action needed',
        body: `We couldn't collect the minimum interested candidates for ${request.jobType} within 24 hours. Choose instant Gixbee Credit or a refund in the app.`,
        data: { type: 'hiring_guarantee_failed', requestId },
      })
      .catch(() => {});
    this.logger.log(
      `[Hiring ${requestId}] guarantee FAILED (${interested}/${request.vacancies} minimum)`,
    );
  }

  private async deliver(
    request: HiringRequest,
    interestedCount: number,
  ): Promise<void> {
    request.status = HiringRequestStatus.DELIVERED;
    request.deliveredAt = new Date();
    await this.requestRepo.save(request);
    await this.notificationsService
      .sendToUser(request.employer.id, {
        title: 'Your candidate shortlist is ready! 🎉',
        body: `${interestedCount} interested ${request.jobType} candidate${interestedCount > 1 ? 's' : ''} — review and shortlist now.`,
        data: { type: 'hiring_delivered', requestId: request.id },
      })
      .catch(() => {});
    this.logger.log(
      `[Hiring ${request.id}] DELIVERED with ${interestedCount} interested`,
    );
  }

  /** Guarantee remedy: instant Gixbee Credit, or flagged refund. */
  async resolveGuarantee(
    employerId: string,
    requestId: string,
    choice: 'CREDIT' | 'REFUND',
  ): Promise<HiringRequest> {
    const request = await this.requestRepo.findOne({
      where: { id: requestId, employer: { id: employerId } },
      relations: ['employer'],
    });
    if (!request) throw new NotFoundException('Hiring request not found');
    if (request.status !== HiringRequestStatus.GUARANTEE_FAILED) {
      throw new BadRequestException(
        'This request is not eligible for a guarantee remedy',
      );
    }
    if (choice === 'CREDIT') {
      await this.walletsService.addFunds(employerId, Number(request.feeAmount));
      request.status = HiringRequestStatus.RESOLVED_CREDIT;
    } else {
      // Refund to original method is processed via the payment gateway /
      // support — recorded here so ops can act and the employer sees status.
      request.status = HiringRequestStatus.RESOLVED_REFUND;
    }
    request.resolvedAt = new Date();
    return this.requestRepo.save(request);
  }

  async listMyRequests(employerId: string): Promise<any[]> {
    const requests = await this.requestRepo.find({
      where: { employer: { id: employerId } },
      order: { createdAt: 'DESC' },
      take: 50,
    });
    return Promise.all(
      requests.map(async (r) => ({
        ...r,
        interestedCount: await this.countInterested(r.id),
      })),
    );
  }

  /**
   * Employer's shortlist view: ONLY interested candidates (the FRD's whole
   * point). Phone number is revealed only after the employer shortlists or
   * hires — pre-decision, employers see the professional summary alone.
   */
  async getRequestDetail(employerId: string, requestId: string): Promise<any> {
    const request = await this.requestRepo.findOne({
      where: { id: requestId, employer: { id: employerId } },
    });
    if (!request) throw new NotFoundException('Hiring request not found');

    const interests = await this.interestRepo.find({
      where: {
        request: { id: requestId },
        response: CandidateResponse.INTERESTED,
      },
      relations: ['candidate', 'preference'],
      order: { respondedAt: 'ASC' },
    });

    const notifiedCount = await this.interestRepo.count({
      where: { request: { id: requestId } },
    });

    return {
      ...request,
      notifiedCount,
      interestedCount: interests.length,
      candidates: interests.map((i) => {
        const revealContact =
          i.decision === EmployerDecision.SHORTLISTED ||
          i.decision === EmployerDecision.HIRED;
        return {
          interestId: i.id,
          name: i.candidate.name,
          phone: revealContact
            ? ((i.candidate as any).phoneNumber ?? null)
            : null,
          decision: i.decision,
          respondedAt: i.respondedAt,
          skills: i.preference?.skills ?? [],
          expectedSalary: i.preference
            ? Number(i.preference.expectedSalary)
            : null,
          experienceYears: i.preference?.experienceYears ?? null,
          noticePeriod: i.preference?.noticePeriod ?? null,
          preferredLocation: i.preference?.preferredLocation ?? null,
        };
      }),
    };
  }

  /** Employer marks Shortlisted / Rejected / Hired — candidate is notified. */
  async setDecision(
    employerId: string,
    interestId: string,
    decision: EmployerDecision,
  ): Promise<HiringInterest> {
    const interest = await this.interestRepo.findOne({
      where: { id: interestId },
      relations: ['request', 'request.employer', 'candidate'],
    });
    if (!interest || interest.request.employer.id !== employerId) {
      throw new NotFoundException('Candidate not found on your request');
    }
    if (interest.response !== CandidateResponse.INTERESTED) {
      throw new BadRequestException(
        'Only interested candidates can be reviewed',
      );
    }
    interest.decision = decision;
    await this.interestRepo.save(interest);

    const messages: Record<EmployerDecision, string> = {
      [EmployerDecision.PENDING]: '',
      [EmployerDecision.SHORTLISTED]: `Great news! You've been shortlisted for ${interest.request.jobType}. The employer may contact you soon.`,
      [EmployerDecision.REJECTED]: `Update on your ${interest.request.jobType} application: the employer went with other candidates this time. Keep your profile active — new openings match automatically.`,
      [EmployerDecision.HIRED]: `Congratulations! 🎉 You've been HIRED for ${interest.request.jobType}!`,
    };
    if (messages[decision]) {
      await this.notificationsService
        .sendToUser(interest.candidate.id, {
          title: 'Hiring status update',
          body: messages[decision],
          data: {
            type: 'hiring_status',
            requestId: interest.request.id,
            decision,
          },
        })
        .catch(() => {});
    }
    return interest;
  }

  // ══════════════════════════════════════════════════════════════════════
  // CANDIDATE — offers + responses
  // ══════════════════════════════════════════════════════════════════════

  /** All offers this candidate was notified about (newest first). */
  async listMyOffers(candidateId: string): Promise<any[]> {
    const interests = await this.interestRepo.find({
      where: { candidate: { id: candidateId } },
      relations: ['request'],
      order: { createdAt: 'DESC' },
      take: 50,
    });
    return interests.map((i) => ({
      interestId: i.id,
      requestId: i.request.id,
      jobType: i.request.jobType,
      location: i.request.location,
      salaryOffered: Number(i.request.salaryOffered),
      skills: i.request.skills ?? [],
      response: i.response,
      decision: i.decision,
      notifiedAt: i.notifiedAt,
      /** Offer stays answerable only while the request is collecting. */
      open:
        i.request.status === HiringRequestStatus.COLLECTING &&
        i.response === CandidateResponse.PENDING,
    }));
  }

  /** Candidate taps Interested / Not Interested. */
  async respond(
    candidateId: string,
    requestId: string,
    interested: boolean,
  ): Promise<{ response: CandidateResponse }> {
    const interest = await this.interestRepo.findOne({
      where: {
        request: { id: requestId },
        candidate: { id: candidateId },
      },
      relations: ['request'],
    });
    if (!interest) {
      throw new NotFoundException('This offer was not sent to you');
    }
    if (interest.response !== CandidateResponse.PENDING) {
      throw new BadRequestException('You have already responded to this offer');
    }
    if (interest.request.status !== HiringRequestStatus.COLLECTING) {
      throw new BadRequestException(
        'This opening is no longer accepting responses',
      );
    }

    interest.response = interested
      ? CandidateResponse.INTERESTED
      : CandidateResponse.NOT_INTERESTED;
    interest.respondedAt = new Date();
    await this.interestRepo.save(interest);

    // Early delivery: target reached before the 24 h deadline.
    if (interested) {
      const request = interest.request;
      const count = await this.countInterested(requestId);
      if (count >= request.targetInterested) {
        const fresh = await this.requestRepo.findOne({
          where: { id: requestId },
          relations: ['employer'],
        });
        if (fresh && fresh.status === HiringRequestStatus.COLLECTING) {
          await this.deliver(fresh, count);
        }
      }
    }
    return { response: interest.response };
  }
}
