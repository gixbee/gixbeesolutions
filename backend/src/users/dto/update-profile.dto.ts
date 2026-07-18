import { IsString, IsOptional, IsBoolean, IsEnum } from 'class-validator';
import { UserRole } from '../user.entity';

// PATCH /admin-user-list/:id — a 1:1 typed replacement of the previous inline
// @Body() literal ({ name?, profileImageUrl?, isAvailableForWork?, role?,
// hasWorkerProfile? }). Every field is optional because this is a partial PATCH
// hit from several call sites with DIFFERENT field sets (traced before writing):
//   - registration_screen.dart → { name, role, hasWorkerProfile }
//       (role is sent as 'OPERATOR'/'OWNER' — both valid UserRole values)
//   - edit_profile_screen.dart → { name }
//   - profile_screen.dart availability toggle → { isAvailableForWork }
//   - super-admin-web user.service.update(id, Partial<User>) → arbitrary subset
// UsersService.updateProfile only PERSISTS name / profileImageUrl /
// isAvailableForWork; role + hasWorkerProfile are accepted-but-ignored today, so
// they are declared here (optional) purely so `whitelist:true` does not strip a
// field the client legitimately sends. No behavioural change — only type/enum
// validation when a field is present.
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
