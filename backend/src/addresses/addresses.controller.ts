import {
  Controller,
  Get,
  Post,
  Delete,
  Param,
  Body,
  UseGuards,
  Req,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AddressesService } from './addresses.service';
import { CreateAddressDto } from './dto/create-address.dto';

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
    });
  }

  @Delete(':id')
  async remove(@Req() req: any, @Param('id') id: string) {
    return this.addresses.remove(req.user.userId, id);
  }
}
