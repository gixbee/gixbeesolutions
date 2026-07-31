import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import {
  AdminStaff,
  AdminStaffRole,
  ADMIN_PORTAL_PAGES,
} from './admin-staff.entity';
import {
  CreateAdminStaffDto,
  UpdateAdminStaffDto,
} from './dto/admin-staff.dto';
import { hashPassword, verifyPassword } from './password.util';

@Injectable()
export class AdminStaffService {
  constructor(
    @InjectRepository(AdminStaff)
    private readonly repo: Repository<AdminStaff>,
  ) {}

  listPages(): { pages: readonly string[] } {
    return { pages: ADMIN_PORTAL_PAGES };
  }

  async findAll(): Promise<Omit<AdminStaff, 'passwordHash'>[]> {
    const rows = await this.repo.find({ order: { createdAt: 'DESC' } });
    return rows.map((r) => this.sanitize(r));
  }

  async findByUsername(username: string): Promise<AdminStaff | null> {
    return this.repo.findOne({
      where: { username: username.trim().toLowerCase() },
    });
  }

  async findById(id: string): Promise<AdminStaff | null> {
    return this.repo.findOne({ where: { id } });
  }

  async create(dto: CreateAdminStaffDto) {
    const username = dto.username.trim().toLowerCase();
    if (await this.findByUsername(username)) {
      throw new ConflictException('Username already exists');
    }
    const pages = this.normalizePages(dto.staffRole, dto.allowedPages);
    const staff = this.repo.create({
      username,
      passwordHash: await hashPassword(dto.password),
      displayName: dto.displayName?.trim() || username,
      staffRole: dto.staffRole,
      allowedPages: pages,
      isActive: true,
    });
    const saved = await this.repo.save(staff);
    return this.sanitize(saved);
  }

  async update(id: string, dto: UpdateAdminStaffDto) {
    const staff = await this.findById(id);
    if (!staff) throw new NotFoundException('Staff user not found');

    if (dto.displayName !== undefined) {
      staff.displayName = dto.displayName.trim() || staff.username;
    }
    if (dto.staffRole !== undefined) staff.staffRole = dto.staffRole;
    if (dto.isActive !== undefined) staff.isActive = dto.isActive;
    if (dto.password) {
      staff.passwordHash = await hashPassword(dto.password);
    }
    if (dto.allowedPages !== undefined || dto.staffRole !== undefined) {
      staff.allowedPages = this.normalizePages(
        staff.staffRole,
        dto.allowedPages ?? staff.allowedPages,
      );
    }

    const saved = await this.repo.save(staff);
    return this.sanitize(saved);
  }

  async remove(id: string): Promise<{ deleted: true }> {
    const staff = await this.findById(id);
    if (!staff) throw new NotFoundException('Staff user not found');
    await this.repo.remove(staff);
    return { deleted: true };
  }

  async validateCredentials(
    username: string,
    password: string,
  ): Promise<AdminStaff | null> {
    const staff = await this.findByUsername(username);
    if (!staff || !staff.isActive) return null;
    const ok = await verifyPassword(password, staff.passwordHash);
    return ok ? staff : null;
  }

  /** Effective page list for JWT / UI. */
  effectivePages(staff: AdminStaff): string[] {
    if (staff.staffRole === AdminStaffRole.SUPER_ADMIN) {
      return [...ADMIN_PORTAL_PAGES];
    }
    return this.normalizePages(AdminStaffRole.OPERATOR, staff.allowedPages);
  }

  private normalizePages(
    role: AdminStaffRole,
    pages?: string[] | null,
  ): string[] {
    if (role === AdminStaffRole.SUPER_ADMIN) {
      return [...ADMIN_PORTAL_PAGES];
    }
    const allowed = new Set<string>(ADMIN_PORTAL_PAGES);
    const cleaned = (pages ?? [])
      .map((p) => p.trim().toLowerCase())
      .filter((p) => allowed.has(p) && p !== 'staff'); // operators never manage staff
    if (cleaned.length === 0) {
      throw new BadRequestException(
        'Operators must be granted at least one portal page',
      );
    }
    return [...new Set(cleaned)];
  }

  private sanitize(staff: AdminStaff) {
    const { passwordHash: _, ...rest } = staff;
    return rest;
  }
}
