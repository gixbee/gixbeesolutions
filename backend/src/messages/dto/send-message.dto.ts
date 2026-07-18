import { IsString, IsNotEmpty, IsOptional } from 'class-validator';

// DTO for POST /messages — previously typed inline as
// `@Body() body: { recipientId: string; body: string; bookingId?: string }`,
// which bypasses the global ValidationPipe (no class metadata to validate
// against). Switching to a class brings the route under the same
// whitelist:true / transform:true pipe as the auth/bookings/talent DTOs.
//
// Traced against the only real client call site —
// chat_repository.dart sendMessage():
//   _dio.post('/messages', data: {
//     'recipientId': recipientId,        // always sent
//     'body': body,                      // always sent
//     if (bookingId != null) 'bookingId': bookingId,   // optional
//   })
// so recipientId + body are always present and bookingId is optional. The
// service signature is send(senderId, recipientId: string, body: string,
// bookingId?: string) and it calls body.trim(), so an empty message is
// meaningless — body is required-non-empty rather than required-but-empty.
export class SendMessageDto {
  @IsString()
  @IsNotEmpty()
  recipientId: string;

  @IsString()
  @IsNotEmpty()
  body: string;

  @IsOptional()
  @IsString()
  bookingId?: string;
}
