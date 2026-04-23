import { Controller, Get, Post, Patch, Param, Body, BadRequestException, UseGuards, Req } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { HiringService } from './hiring.service';
import { ApplicationStatus } from './job-application.entity';

@Controller('hiring')
export class HiringController {
  constructor(private readonly hiringService: HiringService) {}

  @UseGuards(JwtAuthGuard)
  @Post('jobs')
  async createJobPost(
    @Req() req: any,
    @Body() body: { title: string; description: string; requiredSkills?: string[]; salaryMin?: number; salaryMax?: number }
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
    });
  }

  @Get('jobs')
  async getActiveJobs() {
    return this.hiringService.getActiveJobs();
  }

  @Get('jobs/:id')
  async getJobById(@Param('id') id: string) {
    return this.hiringService.getJobById(id);
  }

  @Get('jobs/:id/matches')
  async getTalentMatches(@Param('id') id: string) {
    return this.hiringService.getRecommendedTalent(id);
  }

  @UseGuards(JwtAuthGuard)
  @Post('jobs/:id/apply')
  async applyForJob(
    @Param('id') jobId: string,
    @Req() req: any,
    @Body() body: { coverLetter?: string }
  ) {
    return this.hiringService.applyForJob(jobId, req.user.userId, body.coverLetter);
  }

  @UseGuards(JwtAuthGuard)
  @Get('my-applications')
  async getMyApplications(@Req() req: any) {
    return this.hiringService.getMyApplications(req.user.userId);
  }

  @Get('jobs/:id/applications')
  async getApplicationsForJob(@Param('id') jobId: string) {
    return this.hiringService.getApplicationsForJob(jobId);
  }

  @Patch('applications/:id/status')
  async updateApplicationStatus(
    @Param('id') applicationId: string,
    @Body('status') status: ApplicationStatus
  ) {
    if (!status || !Object.values(ApplicationStatus).includes(status)) {
      throw new BadRequestException('Invalid status provided.');
    }
    return this.hiringService.updateApplicationStatus(applicationId, status);
  }
}
