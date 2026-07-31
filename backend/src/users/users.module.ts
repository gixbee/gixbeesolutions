import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { User } from './user.entity';
import { Booking } from '../bookings/booking.entity';
import { Favourite } from '../favourites/favourite.entity';
import { UsersService } from './users.service';
import { UsersController } from './users.controller';
import { TalentModule } from '../talent/talent.module';

@Module({
  imports: [TypeOrmModule.forFeature([User, Booking, Favourite]), TalentModule],
  providers: [UsersService],
  controllers: [UsersController],
  exports: [TypeOrmModule, UsersService],
})
export class UsersModule {}
