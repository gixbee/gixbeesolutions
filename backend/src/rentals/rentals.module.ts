import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { RentalItem } from './rental-item.entity';
import { RentalReservation } from './rental-reservation.entity';
import { RentalsService } from './rentals.service';
import { RentalsController } from './rentals.controller';

@Module({
  imports: [TypeOrmModule.forFeature([RentalItem, RentalReservation])],
  controllers: [RentalsController],
  providers: [RentalsService],
  exports: [RentalsService],
})
export class RentalsModule {}
