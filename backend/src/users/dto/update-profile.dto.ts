import { IsString, IsOptional, IsBoolean, IsEnum } from 'class-validator';
import { UserRole } from '../user.entity';

// PATCH /admin-user-list/:id — a 1:1 typed replacement of the previous inline
// @Body() literal ({ name?, profileImageUrl?, isAvailableForWork?, role?,
// hasWorkerProfile? }). Every field is optional because this is a partial PATCH
// hit from several call sites with DIFFERENT field sets (traced before writing):
//   - registration_screen.dart → { name } (intent-based; no role at signup)
//   - edit_profile_screen.dart → { name }
//   - profile_screen.dart availability toggle → { isAvailableForWork }
//   - super-admin-web user.service.update(id, Partial<User>) → arbitrary subset
// UsersService.updateProfile persists name / profileImageUrl /
// isAvailableForWork / role / hasWorkerProfile when present. role +
// hasWorkerProfile stay optional so `whitelist:true` does not strip fields
// older clients may still send.
export class UpdateUserProfileDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsString()
  profileImageUrl?: string;

  @IsOptional()
  @IsBoolean()
  isAvailableForWork?: boolean;

  @IsOptional()
  @IsEnum(UserRole)
  role?: UserRole;

  @IsOptional()
  @IsBoolean()
  hasWorkerProfile?: boolean;
}
