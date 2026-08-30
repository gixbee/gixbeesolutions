import {
  EmploymentType,
  employmentTypeMatches,
  parseEmploymentType,
} from './employment-type';

describe('parseEmploymentType', () => {
  it('parses enum codes and labels', () => {
    expect(parseEmploymentType('FT')).toBe(EmploymentType.FT);
    expect(parseEmploymentType('Full Time')).toBe(EmploymentType.FT);
    expect(parseEmploymentType('Part Time')).toBe(EmploymentType.PT);
  });

  it('returns null for empty input', () => {
    expect(parseEmploymentType('')).toBeNull();
    expect(parseEmploymentType(undefined)).toBeNull();
  });
});

describe('employmentTypeMatches', () => {
  it('passes when either side is unset', () => {
    expect(employmentTypeMatches(null, EmploymentType.FT)).toBe(true);
    expect(employmentTypeMatches(EmploymentType.FT, null)).toBe(true);
  });

  it('requires equality when both are set', () => {
    expect(
      employmentTypeMatches(EmploymentType.FT, EmploymentType.FT),
    ).toBe(true);
    expect(
      employmentTypeMatches(EmploymentType.FT, EmploymentType.PT),
    ).toBe(false);
  });
});
