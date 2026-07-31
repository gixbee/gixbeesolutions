import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Body,
  Query,
  UseGuards,
} from '@nestjs/common';
import { MasterEntriesService } from './master-entries.service';
import { MasterEntryType } from './master-entry.entity';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { RequireAdminPage } from '../auth/require-admin-page.decorator';
import {
  CreateMasterEntryDto,
  UpdateMasterEntryDto,
} from './dto/master-entry.dto';

// Read routes (findAll / findOne) stay PUBLIC — the consumer mobile app fetches
// banners / deals / categories from GET /master-entries with no admin login.
// Write routes (create / update / remove) are admin-only: JwtAuthGuard requires a
// valid token and AdminGuard requires role === ADMIN. The super-admin portal gets
// that token from POST /auth/admin-login; a normal consumer JWT is rejected, so
// neither anonymous nor non-admin callers can mutate master data.

@Controller('master-entries')
export class MasterEntriesController {
  constructor(private readonly service: MasterEntriesService) {}

  @Post()
  @UseGuards(JwtAuthGuard, AdminGuard)
  @RequireAdminPage('master-entries')
  async create(@Body() body: CreateMasterEntryDto) {
    return this.service.create(body);
  }

  @Get()
  async findAll(
    @Query('type') type?: MasterEntryType,
    @Query('isActive') isActive?: string,
    @Query('category') category?: string,
    @Query('cityId') cityId?: string,
  ) {
    let _isActive: boolean | undefined = undefined;
    if (isActive === 'true') _isActive = true;
    if (isActive === 'false') _isActive = false;

    return this.service.findAll(type, _isActive, category, cityId || undefined);
  }

  @Get(':id')
  async findOne(@Param('id') id: string) {
    return this.service.findOne(id);
  }

  @Patch(':id')
  @UseGuards(JwtAuthGuard, AdminGuard)
  @RequireAdminPage('master-entries')
  async update(@Param('id') id: string, @Body() body: UpdateMasterEntryDto) {
    return this.service.update(id, body);
  }

  @Delete(':id')
  @UseGuards(JwtAuthGuard, AdminGuard)
  @RequireAdminPage('master-entries')
  async remove(@Param('id') id: string) {
    return this.service.remove(id);
  }
}
