import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn } from 'typeorm';

// Serviceable city master. The consumer app's home location picker lists
// ACTIVE cities from GET /cities (replacing the old hardcoded list in
// home_location_picker_screen.dart), and location-scoped content (banners,
// deals, businesses) references City.id via a nullable cityId column —
// null = global. `lat`/`lng` are the city-centre coordinates, kept so the
// app can auto-detect the nearest active city from GPS. State is a plain
// column (fixed Indian-states dropdown in the admin portal, no master
// needed). Launching a new city = admin inserts a row; no app release.
@Entity('cities')
export class City {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  name: string;

  @Column()
  state: string;

  // City-centre coordinates. `double precision` on Postgres; TypeORM's
  // default numeric handling returns strings for `decimal`, so use 'float'.
  @Column({ type: 'float' })
  lat: number;

  @Column({ type: 'float' })
  lng: number;

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
