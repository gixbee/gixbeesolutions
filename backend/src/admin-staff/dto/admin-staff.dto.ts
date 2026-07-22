import {
  IsArray,
  IsBoolean,
  IsEnum,
  IsOptional,
  IsString,
  MinLength,
  ArrayUnique,
} from 'class-validator';
import { AdminStaffRole } from '../admin-staff.entity';

export class CreateAdminStaffDto {
  @IsString()
  @MinLength(3)
  username: string;

  @IsString()
  @MinLength(8)
  password: string;

  @IsOptional()
  @IsString()
  displayName?: string;

  @IsEnum(AdminStaffRole)
  staffRole: AdminStaffRole;

  @IsOptional()
  @IsArray()
  @ArrayUnique()
  @IsString({ each: true })
  allowedPages?: string[];
}

export class UpdateAdminStaffDto {
  @IsOptional()
  @IsString()
  @MinLength(8)
  password?: string;

  @IsOptional()
  @IsString()
  displayName?: string;

  @IsOptional()
  @IsEnum(AdminStaffRole)
  staffRole?: AdminStaffRole;

  @IsOptional()
  @IsArray()
  @ArrayUnique()
  @IsString({ each: true })
  allowedPages?: string[];

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
