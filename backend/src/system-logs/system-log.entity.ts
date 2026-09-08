import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

/**
 * Severity of a log entry.
 * INFO  — rare (boot/jobs) or client crash ingest; HTTP 2xx is not stored
 * WARN  — client errors (4xx) so you can see bad requests
 * ERROR — server faults (5xx) and unhandled exceptions
 */
export enum SystemLogLevel {
  INFO = 'INFO',
  WARN = 'WARN',
  ERROR = 'ERROR',
}

/**
 * Category of a log entry — the primary filter axis in the admin portal.
 * API       — normal HTTP request/response
 * AUTH      — anything under /auth (logins, OTP, admin-login)
 * DB        — database failures (TypeORM QueryFailedError)
 * SYSTEM    — everything else recorded manually (boot events, jobs, etc.)
 * APP_CRASH — client-side Flutter crashes sent via POST /client-logs
 */
export enum SystemLogType {
  API = 'API',
  AUTH = 'AUTH',
  DB = 'DB',
  SYSTEM = 'SYSTEM',
  APP_CRASH = 'APP_CRASH',
}

/**
 * One row per failure (or Flutter crash), persisted so the super-admin
 * Logs page can show what to fix without SSHing into the box.
 * High-churn table — see SystemLogsService.purge() for retention.
 */
@Entity('system_logs')
export class SystemLog {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column({ type: 'varchar', length: 10, default: SystemLogLevel.INFO })
  level: SystemLogLevel;

  @Index()
  @Column({ type: 'varchar', length: 10, default: SystemLogType.API })
  type: SystemLogType;

  /** HTTP verb (GET/POST/…). Null for non-HTTP entries. */
  @Column({ type: 'varchar', length: 10, nullable: true })
  method: string | null;

  /** Request path incl. query string, capped at 500 chars. */
  @Index()
  @Column({ type: 'varchar', length: 500, nullable: true })
  path: string | null;

  /** HTTP status code returned to the client. */
  @Index()
  @Column({ type: 'int', nullable: true })
  statusCode: number | null;

  /** Wall-clock handler duration in milliseconds. */
  @Column({ type: 'int', nullable: true })
  durationMs: number | null;

  /** userId from the JWT if the request was authenticated. */
  @Column({ type: 'varchar', length: 64, nullable: true })
  userId: string | null;

  /** Caller IP (x-forwarded-for aware behind nginx). */
  @Column({ type: 'varchar', length: 64, nullable: true })
  ip: string | null;

  /** Short human-readable summary (error message, event name…). */
  @Column({ type: 'varchar', length: 500, nullable: true })
  message: string | null;

  /** Long detail — stack trace / driver error. Server-side only, capped. */
  @Column({ type: 'text', nullable: true })
  detail: string | null;

  @Index()
  @CreateDateColumn()
  createdAt: Date;
}
