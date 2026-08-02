/** Shared worker DTO + dispatch constants (avoid circular imports across collaborators). */

export interface WorkerDto {
  id: string;
  name: string;
  title: string;
  bio: string;
  image_url: string;
  rating: number;
  completed_jobs: number;
  review_count: number;
  is_featured: boolean;
  hourly_rate: number;
  skills: string[];
  availability_tags: string[];
  primary_type: string;
  is_active?: boolean;
  status: 'available' | 'busy';
  /** Straight-line distance from the requester in km, rounded to 1 dp.
   *  Only populated by the geo-aware `getNearby` path; absent on the plain
   *  `/workers` list (which has no requester location). */
  distance_km?: number;

  /** Languages the pro speaks (v126 language matching). Absent/empty =
   *  unknown — treated leniently by the broadcast fan-out. */
  languages?: string[];

  /** How far this pro is willing to travel, in km. The dispatch fan-out
   *  only notifies them when distance_km <= this. Absent = legacy profile,
   *  treated as DEFAULT_SERVICE_RADIUS_KM. */
  service_radius_km?: number;
}

/**
 * Hard ceiling on how far any pro can be dispatched (also the GEOSEARCH
 * pre-filter). A pro's own radius is clamped to this.
 *
 * Instant Help is city-scoped via this geo radius — User/WorkerProfile have
 * no cityId yet; City exists only for the app location picker. Do not invent
 * a city schema migration for dispatch.
 */
export const MAX_DISPATCH_RADIUS_KM = 50;

/** Applied to legacy profiles that never set a radius. */
export const DEFAULT_SERVICE_RADIUS_KM = 10;

/**
 * Cap on candidates that proceed to snapshot/status resolution after the
 * distance filter. Prevents unbounded Redis/DB work when the geo index is
 * cold and the skill set is huge (~1k live workers).
 */
export const MAX_NEARBY_CANDIDATES = 40;

/**
 * Hard cap on Instant Help broadcast fan-out (pending queue + FCM/socket).
 * Applied after language filter + nearest/best sort.
 */
export const MAX_BROADCAST_FANOUT = 15;

/** Counting strikes at which a worker is suspended from going live. */
export const SUSPENSION_STRIKE_THRESHOLD = 3;

/** Re-export — single source of truth in common/money-model.ts */
export { WALLET_PAYMENTS_ENABLED } from '../common/money-model';

/**
 * Rebroadcast (attempt 2, nobody accepted in 90s): each pro's own travel
 * radius is stretched by this factor — a job "slightly beyond your usual
 * area" they can still decline. Hard ceiling MAX_DISPATCH_RADIUS_KM applies.
 */
export const REBROADCAST_RADIUS_STRETCH = 1.3;

/** Redis key for the shared (requester-independent) worker directory. */
export const WORKERS_LIST_CACHE_KEY = 'workers:list';
