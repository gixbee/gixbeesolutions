import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Body,
  BadRequestException,
  Query,
  UseGuards,
  Req,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { BusinessesService } from './businesses.service';
import { CreateBusinessDto } from './dto/create-business.dto';
import {
  AddOperatorDto,
  AddOfflineDayDto,
  SetBusinessStatusDto,
} from './dto/business-actions.dto';

@Controller('businesses')
export class BusinessesController {
  constructor(private readonly val: BusinessesService) {}

  @UseGuards(JwtAuthGuard)
  @Post()
  async create(@Req() req: any, @Body() body: CreateBusinessDto) {
    return this.val.create(req.user.userId, body);
  }

  @UseGuards(JwtAuthGuard)
  @Get('my')
  async getMyBusinesses(@Req() req: any) {
    return this.val.getMyBusinesses(req.user.userId);
  }

  // ── Admin: moderation (portal only). Before ':id' so the static segment
  // wins.
  @UseGuards(JwtAuthGuard, AdminGuard)
  @Get('admin/all')
  async adminListAll(@Query('status') status?: string) {
    return this.val.adminListAll(status || undefined);
  }

  @UseGuards(JwtAuthGuard, AdminGuard)
  @Patch('admin/:id/status')
  async adminSetStatus(
    @Param('id') id: string,
    @Body() body: SetBusinessStatusDto,
  ) {
    return this.val.adminSetStatus(id, body.status);
  }

  @Get(':id')
  async getById(@Param('id') id: string) {
    return this.val.getById(id);
  }

  // SECURITY FIX: these mutating routes were UNAUTHENTICATED — anyone could
  // add themselves as an operator of any business by id, or tamper with its
  // calendar. Now JWT-guarded + owner-checked in the service.
  @UseGuards(JwtAuthGuard)
  @Post(':id/operators')
  async addOperator(
    @Param('id') id: string,
    @Req() req: any,
    @Body() body: AddOperatorDto,
  ) {
    if (!body.userId) throw new BadRequestException('userId required');
    return this.val.addOperator(id, body.userId, req.user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @Post(':id/calendar/offline')
  async addOfflineDay(
    @Param('id') id: string,
    @Req() req: any,
    @Body() body: AddOfflineDayDto,
  ) {
    if (!body.date) throw new BadRequestException('date required');
    return this.val.addOfflineDay(id, body.date, req.user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @Delete(':id/calendar/offline')
  async removeOfflineDay(
    @Param('id') id: string,
    @Req() req: any,
    @Query('date') date: string,
  ) {
    if (!date) throw new BadRequestException('date required');
    return this.val.removeOfflineDay(id, date, req.user.userId);
  }
}
