import { Controller, Get, Post, Patch, Param, Query, Body, Req, UseGuards } from '@nestjs/common';
import { WorkersService } from './workers.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@Controller('workers')
@UseGuards(JwtAuthGuard)
export class WorkersController {
  constructor(private readonly workersService: WorkersService) {}

  @Get()
  async getAll(@Req() req) {
    return this.workersService.getAll(req.user.userId);
  }

  // DEFECT-008: Nearby worker search with skill + location filtering
  @Get('nearby')
  async getNearby(
    @Req() req,
    @Query('skill') skill: string,
    @Query('lat') lat: string,
    @Query('lng') lng: string,
  ) {
    return this.workersService.getNearby(req.user.userId, skill, parseFloat(lat), parseFloat(lng));
  }

  @Get(':id')
  async getById(@Param('id') id: string) {
    return this.workersService.getById(id);
  }

  // DEFECT-004 FIX: Use JWT userId instead of URL param to prevent auth bypass
  @Post('live-toggle')
  async toggleGoLive(@Req() req) {
    return this.workersService.toggleGoLive(req.user.userId);
  }

  // DEFECT-006: Worker registration endpoint
  @Post('register')
  async register(@Req() req, @Body() body: {
    skills: string[];
    hourlyRate: number;
    bio?: string;
    title?: string;
  }) {
    return this.workersService.createProfile(req.user.userId, body);
  }

  // DEFECT-007: Hourly rate update with 2/day rate limiting
  @Patch('rate')
  async updateRate(@Req() req, @Body() body: { hourlyRate: number }) {
    return this.workersService.updateHourlyRate(req.user.userId, body.hourlyRate);
  }
}
