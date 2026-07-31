import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';

export enum MasterEntryType {
  CATEGORY = 'CATEGORY',
  SERVICE = 'SERVICE',
  ROLE = 'ROLE',
  CONFIGURATION = 'CONFIGURATION',
  BANNER = 'BANNER',
  DEAL = 'DEAL',
  PRO_TRADE = 'PRO_TRADE',
  PRO_SUB_SKILL = 'PRO_SUB_SKILL',
}

@Entity('master_entries')
export class MasterEntry {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({
    type: 'enum',
    enum: MasterEntryType,
  })
  type: MasterEntryType;

  // The main identifier/label (e.g., 'Plumbing', 'Admin')
  @Column()
  label: string;

  @Column()
  value: string; // The system key or config value

  @Column({ nullable: true })
  icon: string; // Optional icon class or URL for categories

  @Column({ nullable: true })
  category: string; // Optional parent category if nesting is needed

  // Optional location scope: references City.id (cities master). NULL means
  // the entry is GLOBAL — shown in every city. Kept as a plain uuid column
  // (not a relation) so reads stay join-free; the admin portal supplies valid
  // ids from its own city dropdown. GET /master-entries?cityId=… returns
  // global entries + entries scoped to that city (OLX-style city scoping,
  // mainly for BANNER / DEAL content).
  @Column({ type: 'uuid', nullable: true })
  cityId: string | null;

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
