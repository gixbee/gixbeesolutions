import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn } from 'typeorm';

export enum MasterEntryType {
  CATEGORY = 'CATEGORY',
  SERVICE = 'SERVICE',
  ROLE = 'ROLE',
  CONFIGURATION = 'CONFIGURATION',
  BANNER = 'BANNER'
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

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
