import {
  Controller,
  Get,
  Post,
  Patch,
  Param,
  Body,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { SupportService } from './support.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { RequireAdminPage } from '../auth/require-admin-page.decorator';
import { CreateTicketDto, ResolveTicketDto } from './dto/support.dto';
import { parsePagination } from '../common/pagination';

// General support channel: any signed-in user can file a ticket from the
// app's Help & Support screen and read their own tickets; the admin portal
// answers them (AdminGuard routes).
@Controller('support')
@UseGuards(JwtAuthGuard)
export class SupportController {
  constructor(private readonly service: SupportService) {}

  @Post()
  async create(@Req() req: any, @Body() body: CreateTicketDto) {
    return this.service.create(req.user.userId, body.subject, body.message);
  }

  @Get('my')
  async myTickets(@Req() req: any) {
    return this.service.myTickets(req.user.userId);
  }

  @Get('admin/all')
  @UseGuards(AdminGuard)
  @RequireAdminPage('support')
  async adminList(
    @Query('status') status?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = parsePagination(page, limit);
    return this.service.adminList(status || undefined, p.page, p.limit);
  }

  @Patch('admin/:id/resolve')
  @UseGuards(AdminGuard)
  @RequireAdminPage('support')
  async resolve(@Param('id') id: string, @Body() body: ResolveTicketDto) {
    return this.service.resolve(id, body.reply);
  }
}
