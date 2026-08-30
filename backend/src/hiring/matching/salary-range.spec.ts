import {
  normalizeEmployerSalary,
  salaryRangeMatches,
} from './salary-range';

describe('normalizeEmployerSalary', () => {
  it('maps legacy salaryOffered to max with min=floor when not negotiable', () => {
    const s = normalizeEmployerSalary({ salaryOffered: 50000 });
    expect(s.salaryMax).toBe(50000);
    expect(s.salaryMin).toBe(50000);
    expect(s.salaryOffered).toBe(50000);
  });

  it('accepts explicit min/max range', () => {
    const s = normalizeEmployerSalary({
      salaryMin: 30000,
      salaryMax: 50000,
    });
    expect(s.salaryMin).toBe(30000);
    expect(s.salaryMax).toBe(50000);
  });
});

describe('salaryRangeMatches', () => {
  const range = normalizeEmployerSalary({
    salaryMin: 30000,
    salaryMax: 50000,
  });

  it('matches when seeker expectation falls inside employer range', () => {
    expect(
      salaryRangeMatches(range, {
        expectedSalary: 45000,
        salaryNegotiable: false,
      }),
    ).toBe(true);
  });

  it('rejects when seeker expectation exceeds employer max', () => {
    expect(
      salaryRangeMatches(range, {
        expectedSalary: 55000,
        salaryNegotiable: false,
      }),
    ).toBe(false);
  });

  it('widens seeker floor when salaryNegotiable', () => {
    expect(
      salaryRangeMatches(range, {
        expectedSalary: 55000,
        salaryNegotiable: true,
      }),
    ).toBe(true);
  });

  it('widens employer floor when salaryNegotiable', () => {
    const tight = normalizeEmployerSalary({
      salaryMin: 40000,
      salaryMax: 45000,
      salaryNegotiable: true,
    });
    expect(
      salaryRangeMatches(tight, {
        expectedSalary: 35000,
        salaryNegotiable: false,
      }),
    ).toBe(true);
  });
});
