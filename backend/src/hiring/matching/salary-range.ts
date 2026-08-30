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
 * Range overlap for Smart Hiring (V147-03):
 * - Employer budget [min, max]; negotiable → min treated as 0.
 * - Seeker floor = expectedSalary; negotiable → floor treated as 0.
 */
export function salaryRangeMatches(
  employer: EmployerSalaryCriteria,
  pref: Pick<JobPreference, 'expectedSalary' | 'salaryNegotiable'>,
): boolean {
  const empMin = employer.salaryNegotiable ? 0 : employer.salaryMin;
  const empMax = employer.salaryMax;
  const candMin = pref.salaryNegotiable ? 0 : Number(pref.expectedSalary ?? 0);
  const candMax = Number(pref.expectedSalary ?? 0);
  return empMax >= candMin && empMin <= candMax;
}

export function formatSalaryLabel(criteria: EmployerSalaryCriteria): string {
  const { salaryMin, salaryMax } = criteria;
  if (salaryMin > 0 && salaryMin < salaryMax) {
    return `₹${Math.round(salaryMin)}–₹${Math.round(salaryMax)}`;
  }
  return `₹${Math.round(salaryMax)}`;
}
