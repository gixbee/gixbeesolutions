import {
  Controller,
  Get,
  Post,
  Delete,
  Param,
  UseGuards,
  Req,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { FavouritesService } from './favourites.service';

@UseGuards(JwtAuthGuard)
@Controller('favourites')
export class FavouritesController {
  constructor(private readonly favourites: FavouritesService) {}

  @Get()
  async getMyFavourites(@Req() req: any) {
    return this.favourites.getMyFavourites(req.user.userId);
  }

  @Get(':workerId')
  async isFavourite(@Req() req: any, @Param('workerId') workerId: string) {
    return this.favourites.isFavourite(req.user.userId, workerId);
  }

  @Post(':workerId')
  async add(@Req() req: any, @Param('workerId') workerId: string) {
    return this.favourites.add(req.user.userId, workerId);
  }

  @Delete(':workerId')
  async remove(@Req() req: any, @Param('workerId') workerId: string) {
    return this.favourites.remove(req.user.userId, workerId);
  }
}
