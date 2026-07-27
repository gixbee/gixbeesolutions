import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Body,
  UseGuards,
  Req,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AddressesService } from './addresses.service';
import {
  CreateAddressDto,
  UpdateAddressCoordsDto,
} from './dto/create-address.dto';

@UseGuards(JwtAuthGuard)
@Controller('addresses')
export class AddressesController {
  constructor(private readonly addresses: AddressesService) {}

  @Get()
  async getMyAddresses(@Req() req: any) {
    return this.addresses.getMyAddresses(req.user.userId);
  }

  @Post()
  async add(@Req() req: any, @Body() body: CreateAddressDto) {
    return this.addresses.add(req.user.userId, {
      line: body.line,
      label: body.label,
      lat: body.lat,
      lng: body.lng,
    });
  }

  /// Backfill a confirmed map pin onto a saved address that has no coords
  /// yet — after this, Instant Help reuses the pin without opening the map.
  @Patch(':id/coords')
  async updateCoords(
    @Req() req: any,
    @Param('id') id: string,
    @Body() body: UpdateAddressCoordsDto,
  ) {
    return this.addresses.updateCoords(
      req.user.userId,
      id,
      body.lat,
      body.lng,
    );
  }

  @Delete(':id')
  async remove(@Req() req: any, @Param('id') id: string) {
    return this.addresses.remove(req.user.userId, id);
  }
}
