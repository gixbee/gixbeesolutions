import { Controller, Get, Post, Patch, Delete, Param, Body, BadRequestException, Query, UseGuards, Req } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { BusinessesService } from './businesses.service';

@Controller('businesses')
export class BusinessesController {
  constructor(private readonly val: BusinessesService) {}

  @UseGuards(JwtAuthGuard)
  @Post()
  async create(@Req() req: any, @Body() body: any) {
    return this.val.create(req.user.userId, body);
  }

  @UseGuards(JwtAuthGuard)
  @Get('my')
  async getMyBusinesses(@Req() req: any) {
    return this.val.getMyBusinesses(req.user.userId);
  }

  @Get(':id')
  async getById(@Param('id') id: string) {
    return this.val.getById(id);
  }

  @Post(':id/operators')
  async addOperator(@Param('id') id: string, @Body('userId') userId: string) {
    if (!userId) throw new BadRequestException('userId required');
    return this.val.addOperator(id, userId);
  }

  @Post(':id/calendar/offline')
  async addOfflineDay(@Param('id') id: string, @Body('date') date: string) {
    if (!date) throw new BadRequestException('date required');
    return this.val.addOfflineDay(id, date);
  }
}
