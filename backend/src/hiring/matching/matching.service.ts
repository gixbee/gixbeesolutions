import {
  Injectable,
  BadRequestException,
  NotFoundException,
  Logger,
  Inject,
  forwardRef,
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
import { Business } from '../../businesses/business.entity';
import { WalletsService } from '../../wallets/wallets.service';
import { WALLET_PAYMENTS_ENABLED } from '../../common/money-model';
import { NotificationsService } from '../../notifications/notifications.service';
import { PaymentsService } from '../../payments/payments.service';
import {
  EmployerSalaryCriteria,
  EmployerSalaryInput,
  employerSalaryFromRequest,
  formatSalaryLabel,
  normalizeEmployerSalary,
  salaryRangeMatches,
} from './salary-range';

/** POST /hiring/match/requests body (+ Razorpay webhook meta). */
export type HiringMatchRequestDto = EmployerSalaryInput & {
  jobType: string;
  skills?: string[];
  location?: string;
  experienceMinYears?: number;
  vacancies: number;
};

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
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
    @InjectRepository(Business)
    private readonly businessRepo: Repository<Business>,
    private readonly walletsService: WalletsService,
    private readonly notificationsService: NotificationsService,
    @Inject(forwardRef(() => PaymentsService))
    private readonly paymentsService: PaymentsService,
    @InjectQueue('hiring') private readonly hiringQueue: Queue,
  ) {}

  // ── Hiring credit (guarantee CREDIT → next match fee) ──────────────────

  async getHiringCreditBalance(userId: string): Promise<number> {
    const user = await this.userRepo.findOne({ where: { id: userId } });
    return user ? Number(user.hiringCreditBalance) || 0 : 0;
  }

  async addHiringCredit(userId: string, amount: number): Promise<number> {
    const rupees = Math.max(0, Math.round(Number(amount) * 100) / 100);
    if (rupees <= 0) return this.getHiringCreditBalance(userId);
    const user = await this.userRepo.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');
    user.hiringCreditBalance =
      Math.round((Number(user.hiringCreditBalance) + rupees) * 100) / 100;
    await this.userRepo.save(user);
    return Number(user.hiringCreditBalance);
  }

  /** Atomically consume up to `amount`; returns what was actually deducted. */
  async consumeHiringCredit(
    userId: string,
    amount: number,
  ): Promise<number> {
    const want = Math.max(0, Math.round(Number(amount) * 100) / 100);
    if (want <= 0) return 0;
    const user = await this.userRepo.findOne({ where: { id: userId } });
    if (!user) return 0;
    const available = Number(user.hiringCreditBalance) || 0;
    const take = Math.min(available, want);
    if (take <= 0) return 0;
    user.hiringCreditBalance = Math.round((available - take) * 100) / 100;
    await this.userRepo.save(user);
    return take;
  }

  /** Employer must own at least one VERIFIED HIRING business unit. */
  async assertVerifiedHiringBusiness(employerId: string): Promise<void> {
    const count = await this.businessRepo.count({
      where: {
        owner: { id: employerId },
        type: 'HIRING' as any,
        status: 'VERIFIED' as any,
      },
    });
    if (count < 1) {
      throw new BadRequestException(
        'A verified Hiring business is required before you can run Smart Hiring.',
      );
    }
  }

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
      salaryNegotiable?: boolean;
      experienceYears?: number;
      noticePeriod?: NoticePeriod;
    },
  ): Promise<JobPreference | { needsPayment: true; fee: number }> {
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

    // First 2 free; 3rd+ requires Razorpay EXTRA_JOB_TYPE_FEE (webhook creates).
    // Legacy wallet path kept when WALLET_PAYMENTS_ENABLED.
    if (existing.length >= FREE_PREFERENCES) {
      if (WALLET_PAYMENTS_ENABLED) {
        await this.walletsService.charge(
          userId,
          EXTRA_PREFERENCE_FEE,
          `Smart Hiring — extra Job Type "${jobType}" (₹${EXTRA_PREFERENCE_FEE}/month)`,
        );
        return this.saveNewPreference(userId, dto, {
          isPaid: true,
          paidUntil: new Date(Date.now() + 30 * 24 * 3600_000),
        });
      }
      return { needsPayment: true, fee: EXTRA_PREFERENCE_FEE };
    }

    return this.saveNewPreference(userId, dto, {
      isPaid: false,
      paidUntil: null,
    });
  }

  /** Webhook fulfilment for EXTRA_JOB_TYPE_FEE. */
  async createPreferenceFromPayment(
    userId: string,
    dto: {
      jobType: string;
      skills?: string[];
      preferredLocation?: string;
      expectedSalary?: number;
      salaryNegotiable?: boolean;
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
      // Idempotent: payment already fulfilled a duplicate create.
      const pref = existing.find(
        (p) => p.jobType.toLowerCase() === jobType.toLowerCase(),
      )!;
      return pref;
    }
    return this.saveNewPreference(userId, dto, {
      isPaid: true,
      paidUntil: new Date(Date.now() + 30 * 24 * 3600_000),
    });
  }

  private async saveNewPreference(
    userId: string,
    dto: {
      jobType: string;
      skills?: string[];
      preferredLocation?: string;
      expectedSalary?: number;
      salaryNegotiable?: boolean;
      experienceYears?: number;
      noticePeriod?: NoticePeriod;
    },
    flags: { isPaid: boolean; paidUntil: Date | null },
  ): Promise<JobPreference> {
    const pref = this.prefRepo.create({
      user: { id: userId } as User,
      jobType: dto.jobType.trim(),
      skills: (dto.skills ?? []).map((s) => s.trim()).filter(Boolean),
      preferredLocation: dto.preferredLocation?.trim(),
      expectedSalary: dto.expectedSalary ?? 0,
      salaryNegotiable: dto.salaryNegotiable === true,
      experienceYears: Math.max(0, Math.round(dto.experienceYears ?? 0)),
      noticePeriod: dto.noticePeriod ?? NoticePeriod.IMMEDIATE,
      isPaid: flags.isPaid,
      paidUntil: flags.paidUntil,
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
      salaryNegotiable: boolean;
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
    if (dto.salaryNegotiable !== undefined) {
      pref.salaryNegotiable = dto.salaryNegotiable === true;
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
   * Core matcher (FRD + V147-03): jobType equality, salary range overlap,
   * location overlap, minimum experience, ≥1 skill overlap when both sides
   * declared skills. Notice period is delivered to the employer as data
   * rather than used as a hard filter — Indian hiring rarely rejects a good
   * candidate purely on 30-day notice.
   */
  private async findMatchingPreferences(criteria: {
    jobType: string;
    salary: EmployerSalaryCriteria;
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
    let prefs = await qb.getMany();
    prefs = prefs.filter((p) => salaryRangeMatches(criteria.salary, p));

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
    salary: EmployerSalaryCriteria;
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
    dto: HiringMatchRequestDto,
  ): Promise<
    | { request: HiringRequest; estimatedCandidates: number }
    | {
        needsPayment: true;
        fee: number;
        creditApplied: number;
        amountDue: number;
      }
  > {
    await this.assertVerifiedHiringBusiness(employerId);
    const jobType = (dto.jobType || '').trim();
    if (!jobType) throw new BadRequestException('jobType is required');
    const vacancies = Math.max(1, Math.round(dto.vacancies || 1));
    const fee = feeForVacancies(vacancies);
    normalizeEmployerSalary(dto);

    // Legacy wallet charge path when product is on.
    if (WALLET_PAYMENTS_ENABLED) {
      await this.walletsService.charge(
        employerId,
        fee,
        `Smart Hiring — ${jobType} × ${vacancies} vacanc${vacancies > 1 ? 'ies' : 'y'} (24 h guarantee)`,
      );
      return this.startRequest(employerId, dto, {
        feeAmount: fee,
        creditApplied: 0,
        paymentOrderId: null,
        razorpayPaymentId: null,
      });
    }

    const credit = await this.getHiringCreditBalance(employerId);
    const creditApplied = Math.min(credit, fee);
    const amountDue = Math.round((fee - creditApplied) * 100) / 100;

    if (amountDue > 0) {
      return { needsPayment: true, fee, creditApplied, amountDue };
    }

    if (creditApplied > 0) {
      await this.consumeHiringCredit(employerId, creditApplied);
    }
    return this.startRequest(employerId, dto, {
      feeAmount: fee,
      creditApplied,
      paymentOrderId: null,
      razorpayPaymentId: null,
    });
  }

  /** Quote fee + credit for Razorpay order creation (does not start matching). */
  async quoteMatchFee(
    employerId: string,
    vacancies: number,
  ): Promise<{ fee: number; creditApplied: number; amountDue: number }> {
    await this.assertVerifiedHiringBusiness(employerId);
    const fee = feeForVacancies(Math.max(1, Math.round(vacancies || 1)));
    const credit = await this.getHiringCreditBalance(employerId);
    const creditApplied = Math.min(credit, fee);
    const amountDue = Math.round((fee - creditApplied) * 100) / 100;
    return { fee, creditApplied, amountDue };
  }

  /** Webhook fulfilment for HIRING_MATCH_FEE. */
  async createRequestFromPayment(
    employerId: string,
    dto: HiringMatchRequestDto,
    payment: {
      feeAmount: number;
      creditApplied: number;
      paymentOrderId: string;
      razorpayPaymentId: string | null;
    },
  ): Promise<{ request: HiringRequest; estimatedCandidates: number }> {
    await this.assertVerifiedHiringBusiness(employerId);
    const applied = await this.consumeHiringCredit(
      employerId,
      payment.creditApplied || 0,
    );
    return this.startRequest(employerId, dto, {
      feeAmount: payment.feeAmount,
      creditApplied: applied,
      paymentOrderId: payment.paymentOrderId,
      razorpayPaymentId: payment.razorpayPaymentId,
    });
  }

  private async startRequest(
    employerId: string,
    dto: HiringMatchRequestDto,
    payment: {
      feeAmount: number;
      creditApplied: number;
      paymentOrderId: string | null;
      razorpayPaymentId: string | null;
    },
  ): Promise<{ request: HiringRequest; estimatedCandidates: number }> {
    const jobType = dto.jobType.trim();
    const vacancies = Math.max(1, Math.round(dto.vacancies || 1));
    const salary = normalizeEmployerSalary(dto);

    const request = await this.requestRepo.save(
      this.requestRepo.create({
        employer: { id: employerId } as User,
        jobType,
        skills: (dto.skills ?? []).map((s) => s.trim()).filter(Boolean),
        location: dto.location?.trim(),
        salaryOffered: salary.salaryOffered,
        salaryMin: salary.salaryMin,
        salaryMax: salary.salaryMax,
        salaryNegotiable: salary.salaryNegotiable,
        experienceMinYears: Math.max(
          0,
          Math.round(dto.experienceMinYears ?? 0),
        ),
        vacancies,
        targetInterested: vacancies * TARGET_MULTIPLIER,
        feeAmount: payment.feeAmount,
        creditApplied: payment.creditApplied,
        paymentOrderId: payment.paymentOrderId,
        razorpayPaymentId: payment.razorpayPaymentId,
        status: HiringRequestStatus.COLLECTING,
        deadlineAt: new Date(Date.now() + GUARANTEE_WINDOW_HOURS * 3600_000),
      }),
    );

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
      salary,
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
    const salaryCriteria = employerSalaryFromRequest(request);
    const matches = await this.findMatchingPreferences({
      jobType: request.jobType,
      salary: salaryCriteria,
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

    const salaryLabel = formatSalaryLabel(salaryCriteria);
    await this.notificationsService
      .sendToUsers(
        matches.map((p) => p.user.id),
        {
          title: `New ${request.jobType} opening`,
          body: `${salaryLabel}/month · ${request.location || 'your area'} — tap Interested if you want this job.`,
          data: {
            type: 'hiring_offer',
            requestId,
            jobType: request.jobType,
            salary: String(salaryCriteria.salaryMax),
            salaryMin: String(salaryCriteria.salaryMin),
            salaryMax: String(salaryCriteria.salaryMax),
            salaryNegotiable: String(salaryCriteria.salaryNegotiable),
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

  /** Guarantee remedy: instant hiring credit, or Razorpay refund. */
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
    const fee = Number(request.feeAmount) || 0;
    const creditApplied = Number(request.creditApplied) || 0;
    // Only the Razorpay slice was charged at checkout (fee − hiring credit).
    const razorpayPaid = Math.max(
      0,
      Math.round((fee - creditApplied) * 100) / 100,
    );

    if (choice === 'CREDIT') {
      // Full fee back as hiring credit (or wallet when that product is on).
      if (WALLET_PAYMENTS_ENABLED) {
        await this.walletsService.addFunds(employerId, fee);
      } else {
        await this.addHiringCredit(employerId, fee);
      }
      request.status = HiringRequestStatus.RESOLVED_CREDIT;
    } else {
      if (request.razorpayPaymentId && razorpayPaid > 0) {
        await this.paymentsService.refundHiringMatchPayment(
          request.razorpayPaymentId,
          razorpayPaid,
        );
      } else if (WALLET_PAYMENTS_ENABLED && fee > 0) {
        await this.walletsService.addFunds(employerId, fee);
      }
      // Restore hiring credit consumed at request create (covers credit-only
      // hires where creditApplied === fee, and partial-credit + Razorpay).
      if (!WALLET_PAYMENTS_ENABLED && creditApplied > 0) {
        await this.addHiringCredit(employerId, creditApplied);
      }
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
      salaryMin: Number(i.request.salaryMin ?? 0),
      salaryMax: Number(i.request.salaryMax ?? i.request.salaryOffered),
      salaryNegotiable: i.request.salaryNegotiable === true,
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
