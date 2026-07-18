import { Controller, Get, Post, Patch, Delete, Param, Body, Query, UseGuards } from '@nestjs/common';
import { CitiesService } from './cities.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { CreateCityDto, UpdateCityDto } from './dto/city.dto';

// Same access convention as master-entries: reads are PUBLIC (the consumer
// app's location picker calls GET /cities?isActive=true with no login);
// writes are admin-only (super-admin portal token from POST /auth/admin-login).
@Controller('cities')
export class CitiesController {
  constructor(private readonly service: CitiesService) {}

  @Post()
  @UseGuards(JwtAuthGuard, AdminGuard)
  async create(@Body() body: CreateCityDto) {
    return this.service.create(body);
  }

  @Get()
  async findAll(@Query('isActive') isActive?: string) {
    let _isActive: boolean | undefined = undefined;
    if (isActive === 'true') _isActive = true;
    if (isActive === 'false') _isActive = false;
    return this.service.findAll(_isActive);
  }

  @Get(':id')
  async findOne(@Param('id') id: string) {
    return this.service.findOne(id);
  }

  @Patch(':id')
  @UseGuards(JwtAuthGuard, AdminGuard)
  async update(@Param('id') id: string, @Body() body: UpdateCityDto) {
    return this.service.update(id, body);
  }

  @Delete(':id')
  @UseGuards(JwtAuthGuard, AdminGuard)
  async remove(@Param('id') id: string) {
    return this.service.remove(id);
  }
}
