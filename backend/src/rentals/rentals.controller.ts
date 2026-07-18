import { Controller, Get, Post, Patch, Param, Body, BadRequestException, Req, UseGuards, Query } from '@nestjs/common';
import { RentalsService } from './rentals.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateRentalItemDto, UpdateRentalItemDto, RequestReservationDto } from './dto/rentals.dto';
import { parsePagination } from '../common/pagination';

// Rentals: owners list items, customers reserve date/time ranges, owners
// confirm/handover/complete. Identity always comes from the JWT (the old
// spoofable ownerId/renterId body fields were removed).
@Controller('rentals')
@UseGuards(JwtAuthGuard)
export class RentalsController {
  constructor(private readonly rentalsService: RentalsService) {}

  // ── Catalog / items ── (static segments before ':id')

  @Get()
  async getItems() {
    return this.rentalsService.getItems();
  }

  @Get('my-items')
  async getMyItems(
    @Req() req: any,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = parsePagination(page, limit);
    return this.rentalsService.getMyItems(req.user.userId, p.page, p.limit);
  }

  @Get('reservations/my')
  async myReservations(
    @Req() req: any,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = parsePagination(page, limit);
    return this.rentalsService.myReservations(req.user.userId, p.page, p.limit);
  }

  @Get('reservations/owner')
  async ownerReservations(
    @Req() req: any,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = parsePagination(page, limit);
    return this.rentalsService.ownerReservations(
      req.user.userId,
      p.page,
      p.limit,
    );
  }

  @Post()
  async createItem(@Req() req: any, @Body() body: CreateRentalItemDto) {
    return this.rentalsService.createItem(req.user.userId, {
      name: body.name,
      hourlyRate: body.hourlyRate,
      dailyRate: body.dailyRate,
      minHoursToRent: body.minHoursToRent || 1,
      description: body.description,
      imageUrl: body.imageUrl,
    });
  }

  @Patch(':id')
  async updateItem(
    @Param('id') id: string,
    @Req() req: any,
    @Body() body: UpdateRentalItemDto,
  ) {
    return this.rentalsService.updateItem(req.user.userId, id, body);
  }

  @Get(':id')
  async getItemDetail(@Param('id') id: string) {
    return this.rentalsService.getItemDetail(id);
  }

  // ── Reservation lifecycle ──

  @Post(':id/reserve')
  async requestReservation(
    @Param('id') itemId: string,
    @Req() req: any,
    @Body() body: RequestReservationDto,
  ) {
    const start = new Date(body.startTime);
    const end = new Date(body.endTime);
    if (isNaN(start.getTime()) || isNaN(end.getTime())) {
      throw new BadRequestException('Invalid date format provided.');
    }
    return this.rentalsService.requestReservation(
      req.user.userId,
      itemId,
      start,
      end,
    );
  }

  @Patch('reservations/:resId/confirm')
  async confirmReservation(@Param('resId') resId: string, @Req() req: any) {
    return this.rentalsService.confirmReservation(resId, req.user.userId);
  }

  @Patch('reservations/:resId/reject')
  async rejectReservation(@Param('resId') resId: string, @Req() req: any) {
    return this.rentalsService.rejectReservation(resId, req.user.userId);
  }

  @Patch('reservations/:resId/start')
  async startReservation(@Param('resId') resId: string, @Req() req: any) {
    return this.rentalsService.startReservation(resId, req.user.userId);
  }

  @Patch('reservations/:resId/complete')
  async completeReservation(@Param('resId') resId: string, @Req() req: any) {
    return this.rentalsService.completeReservation(resId, req.user.userId);
  }

  @Patch('reservations/:resId/cancel')
  async cancelReservation(@Param('resId') resId: string, @Req() req: any) {
    return this.rentalsService.cancelReservation(resId, req.user.userId);
  }
}
