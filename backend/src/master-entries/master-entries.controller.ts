import { Controller, Get, Post, Patch, Delete, Param, Body, Query, UseGuards } from '@nestjs/common';
import { MasterEntriesService } from './master-entries.service';
import { MasterEntryType } from './master-entry.entity';
// Note: Can protect with JwtAuthGuard and roles later!

@Controller('master-entries')
export class MasterEntriesController {
  constructor(private readonly service: MasterEntriesService) {}

  @Post()
  async create(@Body() body: any) {
    return this.service.create(body);
  }

  @Get()
  async findAll(
    @Query('type') type?: MasterEntryType,
    @Query('isActive') isActive?: string
  ) {
    let _isActive: boolean | undefined = undefined;
    if (isActive === 'true') _isActive = true;
    if (isActive === 'false') _isActive = false;
    
    return this.service.findAll(type, _isActive);
  }

  @Get(':id')
  async findOne(@Param('id') id: string) {
    return this.service.findOne(id);
  }

  @Patch(':id')
  async update(@Param('id') id: string, @Body() body: any) {
    return this.service.update(id, body);
  }

  @Delete(':id')
  async remove(@Param('id') id: string) {
    return this.service.remove(id);
  }
}
