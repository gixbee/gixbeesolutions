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

  @Column({ type: 'text', nullable: true })
  description: string;

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
