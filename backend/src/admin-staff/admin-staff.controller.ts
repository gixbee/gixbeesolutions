import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Req,
  UseGuards,
  ForbiddenException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { RequireAdminPage } from '../auth/require-admin-page.decorator';
import { AdminStaffService } from './admin-staff.service';
import {
  CreateAdminStaffDto,
  UpdateAdminStaffDto,
} from './dto/admin-staff.dto';
import { AdminStaffRole } from './admin-staff.entity';

@Controller('admin-staff')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminStaffController {
  constructor(private readonly staffService: AdminStaffService) {}

  /** Catalog of assignable portal pages (any admin JWT — needed for shell). */
  @Get('pages')
  listPages() {
    return this.staffService.listPages();
  }

  /** Current session profile (pages + role) for the Angular shell. */
  @Get('me')
  me(@Req() req: any) {
    return {
      userId: req.user.userId,
      username: req.user.username ?? 'admin',
      displayName: req.user.displayName ?? 'Admin',
      staffRole: req.user.staffRole ?? AdminStaffRole.SUPER_ADMIN,
      pages: req.user.pages ?? [],
    };
  }

  @Get()
  @RequireAdminPage('staff')
  async list(@Req() req: any) {
    this.assertSuperAdmin(req);
    return this.staffService.findAll();
  }

  @Post()
  @RequireAdminPage('staff')
  async create(@Req() req: any, @Body() body: CreateAdminStaffDto) {
    this.assertSuperAdmin(req);
    return this.staffService.create(body);
  }

  @Patch(':id')
  @RequireAdminPage('staff')
  async update(
    @Req() req: any,
    @Param('id') id: string,
    @Body() body: UpdateAdminStaffDto,
  ) {
    this.assertSuperAdmin(req);
    return this.staffService.update(id, body);
  }

  @Delete(':id')
  @RequireAdminPage('staff')
  async remove(@Req() req: any, @Param('id') id: string) {
    this.assertSuperAdmin(req);
    if (req.user.userId === id) {
      throw new ForbiddenException('You cannot delete your own account');
    }
    return this.staffService.remove(id);
  }

  private assertSuperAdmin(req: any) {
    if (req.user?.staffRole !== AdminStaffRole.SUPER_ADMIN) {
      throw new ForbiddenException('Only super admins can manage staff');
    }
  }
}
