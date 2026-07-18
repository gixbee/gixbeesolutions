import { Controller, Get, Post, Patch, Param, Body, BadRequestException, UseGuards, Req, Query } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { HiringService } from './hiring.service';
import { ApplicationStatus } from './job-application.entity';
import { CreateJobPostDto, ApplyForJobDto, UpdateApplicationStatusDto } from './dto/hiring.dto';
import { parsePagination } from '../common/pagination';

// SECURITY FIX: guard the whole controller. Previously several routes
// (jobs/:id/applications, jobs/:id/matches, applications/:id/status) had NO
// guard — any anonymous caller could read applicant PII or set an
// application to SELECTED/REJECTED/NO_SHOW. Job LISTING reads
// (jobs, jobs/matched, jobs/:id) still only need a valid token, which every
// app user has.
@UseGuards(JwtAuthGuard)
@Controller('hiring')
export class HiringController {
  constructor(private readonly hiringService: HiringService) {}

  @UseGuards(JwtAuthGuard)
  @Post('jobs')
  async createJobPost(
    @Req() req: any,
    @Body() body: CreateJobPostDto
  ) {
    if (!body.title || !body.description) {
      throw new BadRequestException('title and description are required.');
    }
    return this.hiringService.createJobPost(req.user.userId, {
      title: body.title,
      description: body.description,
      requiredSkills: body.requiredSkills || [],
      salaryMin: body.salaryMin,
      salaryMax: body.salaryMax,
      jobType: body.jobType,
      experience: body.experience,
      location: body.location,
    });
  }

  @Get('jobs')
  async getActiveJobs() {
    return this.hiringService.getActiveJobs();
  }

  // Preference-matched feed — needs the seeker identity, so JWT-guarded.
  // Declared before 'jobs/:id' so the static segment wins.
  @UseGuards(JwtAuthGuard)
  @Get('jobs/matched')
  async getMatchedJobs(@Req() req: any) {
    return this.hiringService.getMatchedJobs(req.user.userId);
  }

  @Get('jobs/:id')
  async getJobById(@Param('id') id: string) {
    return this.hiringService.getJobById(id);
  }

  @Get('jobs/:id/matches')
  async getTalentMatches(@Param('id') id: string, @Req() req: any) {
    return this.hiringService.getRecommendedTalent(id, req.user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @Post('jobs/:id/apply')
  async applyForJob(
    @Param('id') jobId: string,
    @Req() req: any,
    @Body() body: ApplyForJobDto
  ) {
    return this.hiringService.applyForJob(jobId, req.user.userId, body.coverLetter, body.resumeUrl);
  }

  @UseGuards(JwtAuthGuard)
  @Get('my-applications')
  async getMyApplications(
    @Req() req: any,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = parsePagination(page, limit);
    return this.hiringService.getMyApplications(
      req.user.userId,
      p.page,
      p.limit,
    );
  }

  @Get('jobs/:id/applications')
  async getApplicationsForJob(
    @Param('id') jobId: string,
    @Req() req: any,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = parsePagination(page, limit);
    return this.hiringService.getApplicationsForJob(
      jobId,
      req.user.userId,
      p.page,
      p.limit,
    );
  }

  @UseGuards(JwtAuthGuard)
  @Post('applications/:id/withdraw')
  async withdrawApplication(
    @Param('id') applicationId: string,
    @Req() req: any,
  ) {
    return this.hiringService.withdrawApplication(applicationId, req.user.userId);
  }

  @Patch('applications/:id/status')
  async updateApplicationStatus(
    @Param('id') applicationId: string,
    @Req() req: any,
    @Body() body: UpdateApplicationStatusDto
  ) {
    const status = body.status;
    if (!status || !Object.values(ApplicationStatus).includes(status)) {
      throw new BadRequestException('Invalid status provided.');
    }
    return this.hiringService.updateApplicationStatus(applicationId, status, req.user.userId);
  }
}
