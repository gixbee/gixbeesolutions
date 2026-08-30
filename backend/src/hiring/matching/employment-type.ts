/** v147 employment type — shared by JobPreference + HiringRequest (V147-02). */
export enum EmploymentType {
  FT = 'FT',
  PT = 'PT',
  INTERN = 'INTERN',
  CONTRACT = 'CONTRACT',
}

const LABEL_TO_CODE: Record<string, EmploymentType> = {
  FT: EmploymentType.FT,
  PT: EmploymentType.PT,
  INTERN: EmploymentType.INTERN,
  CONTRACT: EmploymentType.CONTRACT,
  'FULL TIME': EmploymentType.FT,
  'PART TIME': EmploymentType.PT,
  'FULL-TIME': EmploymentType.FT,
  'PART-TIME': EmploymentType.PT,
};

export const EMPLOYMENT_TYPE_OPTIONS = [
  { code: EmploymentType.FT, label: 'Full Time' },
  { code: EmploymentType.PT, label: 'Part Time' },
  { code: EmploymentType.INTERN, label: 'Intern' },
  { code: EmploymentType.CONTRACT, label: 'Contract' },
] as const;

/** Shared category chips for seeker + employer wizards (mirrors Flutter `_categories`). */
export const JOB_CATEGORY_CATALOG = [
  'Electrician',
  'Plumbing',
  'Cleaning',
  'Painting',
  'Carpentry',
  'AC & Appliances',
  'Driving',
  'Delivery',
  'Cooking',
  'Security',
  'Retail & Sales',
  'Office / Admin',
  'Tech & IT',
  'Teaching',
  'Healthcare',
  'Events',
  'Fitness & Yoga',
  'Beauty',
] as const;

export function parseEmploymentType(
  value: string | undefined | null,
): EmploymentType | null {
  if (!value?.trim()) return null;
  return LABEL_TO_CODE[value.trim().toUpperCase()] ?? null;
}

/** Hard-filter only when both sides declare a type (Kelly V147-02). */
export function employmentTypeMatches(
  employerType: EmploymentType | null | undefined,
  seekerType: EmploymentType | null | undefined,
): boolean {
  if (!employerType || !seekerType) return true;
  return employerType === seekerType;
}
