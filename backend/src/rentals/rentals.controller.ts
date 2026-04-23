import { Controller, Get, Post, Patch, Param, Body, BadRequestException, UseGuards } from '@nestjs/common';
import { RentalsService } from './rentals.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@Controller('rentals')
@UseGuards(JwtAuthGuard)
export class RentalsController {
  constructor(private readonly rentalsService: RentalsService) {}

  @Get()
  async getItems() {
    return this.rentalsService.getItems();
  }

  @Post()
  async createItem(
    @Body() body: { ownerId: string; name: string; hourlyRate: number; minHoursToRent?: number; description?: string }
  ) {
    if (!body.ownerId || !body.name || !body.hourlyRate) {
      throw new BadRequestException('ownerId, name, and hourlyRate are required.');
    }
    return this.rentalsService.createItem(body.ownerId, {
      name: body.name,
      hourlyRate: body.hourlyRate,
      minHoursToRent: body.minHoursToRent || 1,
      description: body.description,
    });
  }

  @Post(':id/reserve')
  async requestReservation(
    @Param('id') itemId: string,
    @Body() body: { renterId: string; startTime: string; endTime: string }
  ) {
    if (!body.renterId || !body.startTime || !body.endTime) {
      throw new BadRequestException('renterId, startTime, and endTime are required.');
    }
    
    // Parse the date strings (e.g. ISO 8601) to Date objects
    const start = new Date(body.startTime);
    const end = new Date(body.endTime);

    if (isNaN(start.getTime()) || isNaN(end.getTime())) {
      throw new BadRequestException('Invalid date format provided.');
    }

    return this.rentalsService.requestReservation(body.renterId, itemId, start, end);
  }

  @Patch('reservations/:resId/confirm')
  async confirmReservation(@Param('resId') reservationId: string) {
    return this.rentalsService.confirmReservation(reservationId);
  }
}
