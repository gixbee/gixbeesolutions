import { parsePagination, DEFAULT_LIMIT, MAX_LIMIT } from './pagination';

describe('parsePagination', () => {
  it('defaults to page 1 / limit 50', () => {
    expect(parsePagination()).toEqual({ page: 1, limit: 50, skip: 0 });
    expect(parsePagination(undefined, undefined)).toEqual({
      page: 1,
      limit: DEFAULT_LIMIT,
      skip: 0,
    });
  });

  it('parses string query values and computes skip', () => {
    expect(parsePagination('3', '20')).toEqual({ page: 3, limit: 20, skip: 40 });
  });

  it('caps limit at MAX_LIMIT', () => {
    expect(parsePagination(1, 999).limit).toBe(MAX_LIMIT);
  });

  it('rejects non-positive / NaN with defaults', () => {
    expect(parsePagination(0, -5)).toEqual({ page: 1, limit: 50, skip: 0 });
    expect(parsePagination('nope', 'bad')).toEqual({
      page: 1,
      limit: 50,
      skip: 0,
    });
  });
});
