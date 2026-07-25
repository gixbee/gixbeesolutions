import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { Exclude } from 'class-transformer';

/** Portal staff role — distinct from mobile UserRole. */
export enum AdminStaffRole {
  /** Full access + can create/edit staff and page maps. */
  SUPER_ADMIN = 'SUPER_ADMIN',
  /** Access only the pages listed in `allowedPages`. */
  OPERATOR = 'OPERATOR',
}

/**
 * Catalog of admin portal pages (route path keys).
 * Keep in sync with super-admin-web routes / sidebar.
 */
export const ADMIN_PORTAL_PAGES = [
  'dashboard',
  'bookings',
  'verifications',
  'disputes',
  'support',
  'businesses',
  'master-entries',
  'cities',
  'users',
  'staff',
  'logs',
  'monitoring',
] as const;

export type AdminPortalPage = (typeof ADMIN_PORTAL_PAGES)[number];

@Entity('admin_staff')
export class AdminStaff {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index({ unique: true })
  @Column({ unique: true })
  username: string;

  @Exclude()
  @Column()
  passwordHash: string;

  @Column({ nullable: true })
  displayName: string;

  @Column({
    type: 'enum',
    enum: AdminStaffRole,
    default: AdminStaffRole.OPERATOR,
  })
  staffRole: AdminStaffRole;

  /**
   * Portal page keys this operator may open.
   * Ignored for SUPER_ADMIN (implicitly all pages).
   */
  @Column('simple-array', { nullable: true })
  allowedPages: string[];

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
