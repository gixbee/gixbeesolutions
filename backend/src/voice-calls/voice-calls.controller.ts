import { Controller, Get, Param, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { VoiceCallsService } from './voice-calls.service';

@Controller('bookings')
@UseGuards(JwtAuthGuard)
export class VoiceCallsController {
  constructor(private readonly voiceCalls: VoiceCallsService) {}

  /** ICE / TURN config for in-app WebRTC voice (participants only). */
  @Get(':id/webrtc-config')
  async getWebRtcConfig(@Param('id') id: string, @Req() req: any) {
    await this.voiceCalls.assertCallableParticipant(id, req.user.userId);
    return this.voiceCalls.getIceServers();
  }
}
