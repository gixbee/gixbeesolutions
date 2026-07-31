/** Shared list pagination — keeps unbounded `find()` from loading entire tables. */

export const DEFAULT_PAGE = 1;
export const DEFAULT_LIMIT = 50;
/** Hard ceiling so clients cannot request huge pages. */
export const MAX_LIMIT = 100;

export type Pagination = {
  page: number;
  limit: number;
  skip: number;
};

/**
 * Parse `?page=&limit=` query values into safe skip/take.
 * Invalid / missing values fall back to page 1, limit 50 (capped at 100).
 */
export function parsePagination(
  page?: string | number,
  limit?: string | number,
  defaultLimit: number = DEFAULT_LIMIT,
): Pagination {
  const rawPage = typeof page === 'string' ? parseInt(page, 10) : Number(page);
  const rawLimit =
    typeof limit === 'string' ? parseInt(limit, 10) : Number(limit);
  const p =
    Number.isFinite(rawPage) && rawPage > 0
      ? Math.floor(rawPage)
      : DEFAULT_PAGE;
  const lRaw =
    Number.isFinite(rawLimit) && rawLimit > 0
      ? Math.floor(rawLimit)
      : defaultLimit;
  const l = Math.min(MAX_LIMIT, Math.max(1, lRaw));
  return { page: p, limit: l, skip: (p - 1) * l };
}
