import { IsString, IsNotEmpty, MaxLength } from 'class-validator';

// POST /support — app's Help & Support contact form.
export class CreateTicketDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  subject: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(4000)
  message: string;
}

// PATCH /support/admin/:id/resolve — portal reply.
export class ResolveTicketDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(4000)
  reply: string;
}
