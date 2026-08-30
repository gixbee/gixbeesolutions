import { BadRequestException } from '@nestjs/common';
import { JobPreference } from './job-preference.entity';
import { HiringRequest } from './hiring-request.entity';

/** Normalized employer budget for Smart Hiring matcher (₹/month). */
export interface EmployerSalaryCriteria {
  salaryMin: number;
  salaryMax: number;
  salaryNegotiable: boolean;
  /** Legacy column — always mirrors `salaryMax`. */
  salaryOffered: number;
}

export type EmployerSalaryInput = {
  salaryOffered?: number;
  salaryMin?: number;
  salaryMax?: number;
  salaryNegotiable?: boolean;
};

/** Accept legacy `salaryOffered` or explicit min/max range. */
export function normalizeEmployerSalary(
  input: EmployerSalaryInput,
): EmployerSalaryCriteria {
  const negotiable = input.salaryNegotiable === true;
  const offered = Number(input.salaryOffered ?? 0);
  let max = Number(input.salaryMax ?? 0);
  let min = Number(input.salaryMin ?? 0);

  if (!(max > 0) && offered > 0) max = offered;
  if (!(max > 0)) {
    throw new BadRequestException(
      'salaryMax or salaryOffered (₹/month) is required',
    );
  }
  if (!(min > 0) && !negotiable && offered > 0 && !input.salaryMax) {
    min = offered;
  }
  if (min < 0) min = 0;
  if (min > max) {
    throw new BadRequestException('salaryMin cannot exceed salaryMax');
  }

  return {
    salaryMin: min,
    salaryMax: max,
    salaryNegotiable: negotiable,
    salaryOffered: max,
  };
}

export function employerSalaryFromRequest(
  request: Pick<
    HiringRequest,
    'salaryMin' | 'salaryMax' | 'salaryOffered' | 'salaryNegotiable'
  >,
): EmployerSalaryCriteria {
  return normalizeEmployerSalary({
    salaryMin: Number(request.salaryMin ?? 0),
    salaryMax: Number(request.salaryMax ?? request.salaryOffered ?? 0),
    salaryOffered: Number(request.salaryOffered ?? 0),
    salaryNegotiable: request.salaryNegotiable === true,
  });
}

/**
 * Smart Hiring salary match (V147-03 — Kelly/Jan contract):
 * `expectedSalary <= salaryMax` AND
 * (`salaryNegotiable` OR `expectedSalary >= effectiveMin`).
 * Employer negotiable treats min as 0.
 */
export function salaryRangeMatches(
  employer: EmployerSalaryCriteria,
  pref: Pick<JobPreference, 'expectedSalary' | 'salaryNegotiable'>,
): boolean {
  const expected = Number(pref.expectedSalary ?? 0);
  const effectiveMin = employer.salaryNegotiable ? 0 : employer.salaryMin;
  return (
    expected <= employer.salaryMax &&
    (pref.salaryNegotiable === true || expected >= effectiveMin)
  );
}

export function formatSalaryLabel(criteria: EmployerSalaryCriteria): string {
  const { salaryMin, salaryMax } = criteria;
  if (salaryMin > 0 && salaryMin < salaryMax) {
    return `₹${Math.round(salaryMin)}–₹${Math.round(salaryMax)}`;
  }
  return `₹${Math.round(salaryMax)}`;
}
