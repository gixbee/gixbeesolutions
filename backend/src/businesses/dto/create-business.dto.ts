import { IsString, IsNotEmpty, IsOptional, IsUUID } from 'class-validator';

// POST /businesses — validates the list-my-business payload. Fields mirror
// EXACTLY Business.toJson() in the Flutter client (lib/shared/models/business.dart):
// name, type, description, specialty, phone, address. The service does
// businessRepo.create({ ...data, owner, status:'PENDING' }); only name/type/
// description are persisted columns — specialty/phone/address are sent by the
// client today and ignored by TypeORM, so they are declared here (optional) to
// keep `whitelist:true` from stripping anything the client sends. Only name +
// type are required (both are non-nullable columns and always sent).
export class CreateBusinessDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsString()
  @IsNotEmpty()
  type: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  specialty?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsString()
  address?: string;

  // Optional uploaded registration/tax-ID document URL (persisted column).
  @IsOptional()
  @IsString()
  documentUrl?: string;

  // Optional structured city scope — City.id from the cities master
  // (persisted column; filtering uses this, `address`/`location` stay
  // free-text display strings).
  @IsOptional()
  @IsUUID()
  cityId?: string;
}
