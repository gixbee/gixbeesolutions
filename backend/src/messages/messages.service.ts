import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Brackets } from 'typeorm';
import { Message } from './message.entity';
import { User } from '../users/user.entity';
import { MessagesGateway } from './messages.gateway';

export interface MessageDto {
  id: string;
  body: string;
  bookingId: string | null;
  isRead: boolean;
  createdAt: Date;
  senderId: string;
  recipientId: string;
}

export interface ConversationDto {
  userId: string;
  name: string;
  phoneNumber: string;
  lastMessage: string;
  lastAt: Date;
  unread: number;
}

@Injectable()
export class MessagesService {
  constructor(
    @InjectRepository(Message)
    private readonly messagesRepo: Repository<Message>,
    @InjectRepository(User)
    private readonly usersRepo: Repository<User>,
    private readonly gateway: MessagesGateway,
  ) {}

  private toDto(m: Message): MessageDto {
    return {
      id: m.id,
      body: m.body,
      bookingId: m.bookingId,
      isRead: m.isRead,
      createdAt: m.createdAt,
      senderId: m.sender?.id,
      recipientId: m.recipient?.id,
    };
  }

  /** Send a message and push it to the recipient's socket room. */
  async send(
    senderId: string,
    recipientId: string,
    body: string,
    bookingId?: string,
  ): Promise<MessageDto> {
    const recipient = await this.usersRepo.findOne({
      where: { id: recipientId },
    });
    if (!recipient) throw new NotFoundException('Recipient not found');

    const message = this.messagesRepo.create({
      sender: { id: senderId } as User,
      recipient: { id: recipientId } as User,
      body: body.trim(),
      bookingId: bookingId ?? null,
      isRead: false,
    });
    const saved = await this.messagesRepo.save(message);

    // Re-load with relations so the DTO/payload carries sender + recipient ids
    const full = await this.messagesRepo.findOne({ where: { id: saved.id } });
    const dto = this.toDto(full ?? saved);

    this.gateway.emitToUser(recipientId, { ...dto, _event: 'new_message' });
    return dto;
  }

  /** All messages between the two users, oldest first. Marks unread→read. */
  async getThread(userId: string, otherUserId: string): Promise<MessageDto[]> {
    const messages = await this.messagesRepo
      .createQueryBuilder('m')
      .leftJoinAndSelect('m.sender', 'sender')
      .leftJoinAndSelect('m.recipient', 'recipient')
      .where(
        new Brackets((qb) => {
          qb.where('sender.id = :userId AND recipient.id = :otherUserId', {
            userId,
            otherUserId,
          }).orWhere('sender.id = :otherUserId AND recipient.id = :userId', {
            userId,
            otherUserId,
          });
        }),
      )
      .orderBy('m.createdAt', 'ASC')
      .getMany();

    // Mark messages addressed to me as read
    await this.messagesRepo
      .createQueryBuilder()
      .update(Message)
      .set({ isRead: true })
      .where(
        'recipientId = :userId AND senderId = :otherUserId AND isRead = false',
        {
          userId,
          otherUserId,
        },
      )
      .execute();

    return messages.map((m) => this.toDto(m));
  }

  /** One entry per conversation partner, newest activity first. */
  async getConversations(userId: string): Promise<ConversationDto[]> {
    const messages = await this.messagesRepo
      .createQueryBuilder('m')
      .leftJoinAndSelect('m.sender', 'sender')
      .leftJoinAndSelect('m.recipient', 'recipient')
      .where('sender.id = :userId OR recipient.id = :userId', { userId })
      .orderBy('m.createdAt', 'DESC')
      .getMany();

    const byPartner = new Map<string, ConversationDto>();
    for (const m of messages) {
      const partner = m.sender?.id === userId ? m.recipient : m.sender;
      if (!partner) continue;
      const existing = byPartner.get(partner.id);
      const isUnreadForMe = m.recipient?.id === userId && !m.isRead;
      if (!existing) {
        byPartner.set(partner.id, {
          userId: partner.id,
          name: partner.name || 'Gixbee user',
          phoneNumber: partner.phoneNumber,
          lastMessage: m.body,
          lastAt: m.createdAt,
          unread: isUnreadForMe ? 1 : 0,
        });
      } else if (isUnreadForMe) {
        existing.unread += 1;
      }
    }
    return Array.from(byPartner.values());
  }
}
