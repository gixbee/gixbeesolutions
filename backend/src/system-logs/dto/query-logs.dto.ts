import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';
import { SystemLogLevel, SystemLogType } from '../system-log.entity';

export class QueryLogsDto {
  @IsOptional()
  @IsEnum(SystemLogType)
  type?: SystemLogType;

  @IsOptional()
  @IsEnum(SystemLogLevel)
  level?: SystemLogLevel;

  /** 'true' / '1' → WARN + ERROR only. */
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true' || value === '1')
  @IsBoolean()
  problems?: boolean;

  /** e.g. 1000 → durationMs >= 1000. */
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(600_000)
  minDurationMs?: number;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  method?: string;

  /** '404' | '4xx' | '5xx' … */
  @IsOptional()
  @Matches(/^(\d{3}|[1-5]xx)$/i, {
    message: 'status must be a 3-digit code or a class like 4xx',
  })
  status?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  search?: string;

  @IsOptional()
  @IsISO8601()
  from?: string;

  @IsOptional()
  @IsISO8601()
  to?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number;
}

export class PurgeLogsDto {
  /** Delete entries older than this many days. */
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(365)
  olderThanDays: number;
}
