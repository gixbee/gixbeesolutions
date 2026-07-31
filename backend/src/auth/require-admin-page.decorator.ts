import { SetMetadata } from '@nestjs/common';
import { AdminPortalPage } from '../admin-staff/admin-staff.entity';

/** Metadata key read by AdminGuard for portal page ACL. */
export const ADMIN_PAGES_KEY = 'admin_pages';

/**
 * Restrict an ADMIN-guarded route to operators whose JWT `pages` include at
 * least one of the listed portal page keys. SUPER_ADMIN always passes.
 *
 * Apply on the handler (or controller) that already uses AdminGuard:
 *   @UseGuards(JwtAuthGuard, AdminGuard)
 *   @RequireAdminPage('users')
 */
export const RequireAdminPage = (...pages: AdminPortalPage[]) =>
  SetMetadata(ADMIN_PAGES_KEY, pages);
