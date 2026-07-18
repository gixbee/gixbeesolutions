import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SupportTicket } from './support-ticket.entity';
import { NotificationsService } from '../notifications/notifications.service';

@Injectable()
export class SupportService {
  constructor(
    @InjectRepository(SupportTicket)
    private readonly ticketRepo: Repository<SupportTicket>,
    private readonly notificationsService: NotificationsService,
  ) {}

  async create(userId: string, subject: string, message: string): Promise<SupportTicket> {
    const ticket = this.ticketRepo.create({
      user: { id: userId } as any,
      subject,
      message,
      status: 'OPEN',
    });
    return this.ticketRepo.save(ticket);
  }

  async myTickets(userId: string): Promise<SupportTicket[]> {
    return this.ticketRepo.find({
      where: { user: { id: userId } },
      order: { createdAt: 'DESC' },
    });
  }

  // ── Admin ──────────────────────────────────────────────────────────────────

  async adminList(status?: string): Promise<SupportTicket[]> {
    const where: any = {};
    if (status) where.status = status;
    return this.ticketRepo.find({
      where,
      relations: ['user'],
      order: { createdAt: 'DESC' },
    });
  }

  async resolve(ticketId: string, reply: string): Promise<SupportTicket> {
    const ticket = await this.ticketRepo.findOne({
      where: { id: ticketId },
      relations: ['user'],
    });
    if (!ticket) throw new NotFoundException('Ticket not found');
    if (ticket.status === 'RESOLVED') {
      throw new BadRequestException('Ticket is already resolved');
    }
    ticket.reply = reply;
    ticket.status = 'RESOLVED';
    ticket.resolvedAt = new Date();
    await this.ticketRepo.save(ticket);

    if (ticket.user?.id) {
      await this.notificationsService
        .sendToUser(ticket.user.id, {
          title: 'Support replied',
          body: `Your ticket "${ticket.subject}" has been answered — check Help & Support.`,
          data: { type: 'support_reply', ticketId: ticket.id },
        })
        .catch(() => {});
    }
    return ticket;
  }
}
