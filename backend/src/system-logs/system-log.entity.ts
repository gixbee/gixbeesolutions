import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

/**
 * Severity of a log entry.
 * INFO  — successful requests (2xx/3xx)
 * WARN  — expected client errors (4xx)
 * ERROR — server faults (5xx) and unhandled exceptions
 */
export enum SystemLogLevel {
  INFO = 'INFO',
  WARN = 'WARN',
  ERROR = 'ERROR',
}

/**
 * Category of a log entry — the primary filter axis in the admin portal.
 * API    — normal HTTP request/response
 * AUTH   — anything under /auth (logins, OTP, admin-login)
 * DB     — database failures (TypeORM QueryFailedError)
 * SYSTEM — everything else recorded manually (boot events, jobs, etc.)
 */
export enum SystemLogType {
  API = 'API',
  AUTH = 'AUTH',
  DB = 'DB',
  SYSTEM = 'SYSTEM',
}

/**
 * One row per API call / error, persisted by ApiLoggingInterceptor so the
 * super-admin portal can browse & filter production traffic without SSHing
 * into the box. High-churn table — see SystemLogsService.purge() for retention.
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
