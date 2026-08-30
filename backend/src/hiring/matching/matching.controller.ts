import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Query,
  Body,
  Req,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { MatchingService, feeForVacancies } from './matching.service';
import { normalizeEmployerSalary } from './salary-range';
import { NoticePeriod } from './job-preference.entity';
import { EmployerDecision } from './hiring-interest.entity';

/**
 * Smart Hiring (FRD: Find a Job + Hire Employee, connected by the matching
 * engine). All endpoints JWT-guarded; employer endpoints operate on the
 * caller's own requests only.
 */
@Controller('hiring/match')
@UseGuards(JwtAuthGuard)
export class MatchingController {
  constructor(private readonly matchingService: MatchingService) {}

  // ── Candidate: Job Type preference profiles ──────────────────────────────

  @Get('preferences')
  async myPreferences(@Req() req) {
    return this.matchingService.listMyPreferences(req.user.userId);
  }

  @Post('preferences')
  async createPreference(
    @Req() req,
    @Body()
    body: {
      jobType: string;
      skills?: string[];
      preferredLocation?: string;
      expectedSalary?: number;
      salaryNegotiable?: boolean;
      experienceYears?: number;
      noticePeriod?: NoticePeriod;
    },
  ) {
    return this.matchingService.createPreference(req.user.userId, body);
  }

  @Patch('preferences/:id')
  async updatePreference(
    @Req() req,
    @Param('id') id: string,
    @Body()
    body: {
      skills?: string[];
      preferredLocation?: string;
      expectedSalary?: number;
      salaryNegotiable?: boolean;
      experienceYears?: number;
      noticePeriod?: NoticePeriod;
      jobType?: string;
    },
  ) {
    return this.matchingService.updatePreference(req.user.userId, id, body);
  }

  @Delete('preferences/:id')
  async deletePreference(@Req() req, @Param('id') id: string) {
    await this.matchingService.deletePreference(req.user.userId, id);
    return { deleted: true };
  }

  // ── Candidate: offers + Interested / Not Interested ─────────────────────

  @Get('offers')
  async myOffers(@Req() req) {
    return this.matchingService.listMyOffers(req.user.userId);
  }

  @Post('offers/:requestId/respond')
  async respond(
    @Req() req,
    @Param('requestId') requestId: string,
    @Body() body: { interested: boolean },
  ) {
    return this.matchingService.respond(
      req.user.userId,
      requestId,
      body?.interested === true,
    );
  }

  // ── Employer: estimate, create, review ───────────────────────────────────

  /** Salary-slider live estimate. skills = comma-separated. */
  @Get('estimate')
  async estimate(
    @Query('jobType') jobType: string,
    @Query('salary') salary: string,
    @Query('salaryMin') salaryMin?: string,
    @Query('salaryMax') salaryMax?: string,
    @Query('salaryNegotiable') salaryNegotiable?: string,
    @Query('location') location?: string,
    @Query('experienceMin') experienceMin?: string,
    @Query('skills') skills?: string,
  ) {
    const salaryCriteria = normalizeEmployerSalary({
      salaryOffered: parseFloat(salary) || 0,
      salaryMin: salaryMin !== undefined ? parseFloat(salaryMin) : undefined,
      salaryMax: salaryMax !== undefined ? parseFloat(salaryMax) : undefined,
      salaryNegotiable: salaryNegotiable === 'true' || salaryNegotiable === '1',
    });
    return this.matchingService.estimateCandidates({
      jobType: jobType ?? '',
      salary: salaryCriteria,
      location,
      experienceMinYears: experienceMin ? parseInt(experienceMin, 10) : 0,
      skills: skills
        ? skills
            .split(',')
            .map((s) => s.trim())
            .filter(Boolean)
        : [],
    });
  }

  /** Pricing table for the app's payment sheet (₹49/99/199/399 tiers). */
  @Get('pricing')
  pricing() {
    return {
      tiers: [
        { maxVacancies: 1, fee: feeForVacancies(1) },
        { maxVacancies: 5, fee: feeForVacancies(5) },
        { maxVacancies: 10, fee: feeForVacancies(10) },
        { maxVacancies: 25, fee: feeForVacancies(25) },
      ],
      guaranteeHours: 24,
      extraJobTypeFee: 50,
    };
  }

  /** Hiring credit balance (guarantee CREDIT applied to next match fee). */
  @Get('credit')
  async credit(@Req() req) {
    const balance = await this.matchingService.getHiringCreditBalance(
      req.user.userId,
    );
    return { balance };
  }

  @Post('requests')
  async createRequest(@Req() req, @Body() body: Record<string, unknown>) {
    return this.matchingService.createRequest(req.user.userId, {
      jobType: String(body.jobType ?? ''),
      skills: Array.isArray(body.skills) ? (body.skills as string[]) : [],
      location: body.location as string | undefined,
      salaryOffered: body.salaryOffered as number | undefined,
      salaryMin: body.salaryMin as number | undefined,
      salaryMax: body.salaryMax as number | undefined,
      salaryNegotiable: body.salaryNegotiable === true,
      experienceMinYears: Number(body.experienceMinYears) || 0,
      vacancies: Number(body.vacancies) || 1,
    });
  }

  @Get('requests')
  async myRequests(@Req() req) {
    return this.matchingService.listMyRequests(req.user.userId);
  }

  @Get('requests/:id')
  async requestDetail(@Req() req, @Param('id') id: string) {
    return this.matchingService.getRequestDetail(req.user.userId, id);
  }

  /** Guarantee remedy after a failed 24 h window: CREDIT (instant) or REFUND. */
  @Post('requests/:id/resolve')
  async resolveGuarantee(
    @Req() req,
    @Param('id') id: string,
    @Body() body: { choice: 'CREDIT' | 'REFUND' },
  ) {
    return this.matchingService.resolveGuarantee(
      req.user.userId,
      id,
      body?.choice === 'REFUND' ? 'REFUND' : 'CREDIT',
    );
  }

  @Patch('interests/:id/decision')
  async setDecision(
    @Req() req,
    @Param('id') id: string,
    @Body() body: { decision: EmployerDecision },
  ) {
    return this.matchingService.setDecision(req.user.userId, id, body.decision);
  }
}
