import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, ManyToOne } from 'typeorm';
import { User } from '../users/user.entity';

@Entity('businesses')
export class Business {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => User)
  owner: User;

  @Column({ type: 'enum', enum: ['SERVICE', 'HIRING', 'RENTAL'] })
  type: string;

  @Column({ type: 'enum', enum: ['HALL', 'CATERING', 'DECORATION', 'PHOTOGRAPHY'], nullable: true })
  serviceType: string;

  @Column()
  name: string;

  @Column()
  location: string;

  // Structured location scope: City.id from the cities master (nullable —
  // legacy rows and listings created before a city was chosen have null).
  // `location` above stays as the free-text display string; cityId is what
  // filtering uses (OLX-style city scoping).
  @Column({ type: 'uuid', nullable: true })
  cityId: string | null;

  @Column({ type: 'text', nullable: true })
  description: string;

  // Optional registration / tax-ID document image uploaded during listing
  // (POST /uploads/image → URL). Persisted so admin review can see it.
  @Column({ type: 'text', nullable: true })
  documentUrl: string;

  @Column({ type: 'enum', enum: ['PENDING', 'VERIFIED', 'REJECTED'], default: 'PENDING' })
  status: string;

  // We could create an Operator mapping table, but keeping it as a simple-array or relation is fine for V1
  @Column('simple-array', { nullable: true })
  operatorIds: string[];

  @Column('simple-json', { nullable: true })
  offlineDays: string[];

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
