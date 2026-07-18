import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Req,
  UseGuards,
} from '@nestjs/common';
import { MessagesService } from './messages.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SendMessageDto } from './dto/send-message.dto';

@Controller('messages')
@UseGuards(JwtAuthGuard)
export class MessagesController {
  constructor(private readonly messagesService: MessagesService) {}

  /** Inbox: one row per conversation partner. */
  @Get('conversations')
  async conversations(@Req() req) {
    return this.messagesService.getConversations(req.user.userId);
  }

  /** Full thread with one user (marks their messages to me as read). */
  @Get('thread/:userId')
  async thread(@Req() req, @Param('userId') userId: string) {
    return this.messagesService.getThread(req.user.userId, userId);
  }

  /** Send a message. */
  @Post()
  async send(
    @Req() req,
    @Body() body: SendMessageDto,
  ) {
    return this.messagesService.send(
      req.user.userId,
      body.recipientId,
      body.body,
      body.bookingId,
    );
  }
}
