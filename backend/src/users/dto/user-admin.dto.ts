import { IsString, IsNotEmpty, IsEnum, IsBoolean } from 'class-validator';
import { SkillApprovalStatus } from '../../talent/professional-skill.entity';
import { UserApprovalStatus } from '../user.entity';

// DTOs for the admin-user-list single-field write endpoints. These previously
// used `@Body('token')` / `@Body('status')` / `@Body('isVerified')` primitive
// extraction, which the global ValidationPipe (whitelist + transform, main.ts)
// cannot validate. Field names mirror EXACTLY what the callers send so
// `whitelist:true` strips nothing legitimate:
//   - super-admin-web user.service.ts → PATCH :id/verify { isVerified },
//     PATCH :id/status { status }, PATCH skill/:skillId/status { status }.
//   - :id/fcm-token { token } currently has no live caller; the DTO keeps the
//     endpoint consistent should one be added.

export class UpdateFcmTokenDto {
  @IsString()
  @IsNotEmpty()
  token: string;
}

export class UpdateSkillStatusDto {
  @IsEnum(SkillApprovalStatus)
  status: SkillApprovalStatus;
}

export class UpdateUserStatusDto {
  @IsEnum(UserApprovalStatus)
  status: UserApprovalStatus;
}

export class VerifyUserDto {
  @IsBoolean()
  isVerified: boolean;
}
