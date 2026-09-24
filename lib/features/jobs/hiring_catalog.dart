import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/matching_repository.dart';

/// Shared Smart Hiring taxonomy from `GET /hiring/match/catalog` (V147-02).
class HiringCatalog {
  final List<EmploymentTypeOption> employmentTypes;
  final List<String> categories;

  const HiringCatalog({
    required this.employmentTypes,
    required this.categories,
  });

  static const fallback = HiringCatalog(
    employmentTypes: [
      EmploymentTypeOption(code: 'FT', label: 'Full Time'),
      EmploymentTypeOption(code: 'PT', label: 'Part Time'),
      EmploymentTypeOption(code: 'INTERN', label: 'Intern'),
      EmploymentTypeOption(code: 'CONTRACT', label: 'Contract'),
    ],
    categories: [
      'Electrician', 'Plumbing', 'Cleaning', 'Painting', 'Carpentry',
      'AC & Appliances', 'Driving', 'Delivery', 'Cooking', 'Security',
      'Retail & Sales', 'Office / Admin', 'Tech & IT', 'Teaching',
      'Healthcare', 'Events', 'Fitness & Yoga', 'Beauty',
    ],
  );

  factory HiringCatalog.fromJson(Map<String, dynamic> json) {
    final types = (json['employmentTypes'] as List? ?? [])
        .map((e) => EmploymentTypeOption.fromJson(
            Map<String, dynamic>.from(e as Map)))
        .toList();
    final cats = (json['categories'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    return HiringCatalog(
      employmentTypes: types.isNotEmpty ? types : fallback.employmentTypes,
      categories: cats.isNotEmpty ? cats : fallback.categories,
    );
  }

  String labelForCode(String? code) {
    if (code == null || code.isEmpty) return '';
    for (final t in employmentTypes) {
      if (t.code == code) return t.label;
    }
    return code;
  }
}

class EmploymentTypeOption {
  final String code;
  final String label;

  const EmploymentTypeOption({required this.code, required this.label});

  factory EmploymentTypeOption.fromJson(Map<String, dynamic> json) =>
      EmploymentTypeOption(
        code: json['code']?.toString() ?? '',
        label: json['label']?.toString() ?? json['code']?.toString() ?? '',
      );
}

/// Formats employer offer salary for Alerts cards.
String formatOfferSalary(Map<String, dynamic> offer) {
  final min = (offer['salaryMin'] as num?)?.toInt();
  final max = (offer['salaryMax'] as num?)?.toInt() ??
      (offer['salaryOffered'] as num?)?.toInt();
  final negotiable = offer['salaryNegotiable'] == true;
  if (max == null || max <= 0) return '';
  final period = _salaryPeriodSuffix(offer['salaryPeriod']?.toString());
  final range = min != null && min > 0 && min < max
      ? '₹$min–₹$max/$period'
      : '₹$max/$period';
  return negotiable ? '$range · negotiable' : range;
}

String _salaryPeriodSuffix(String? period) {
  switch (period) {
    case 'HOURLY':
      return 'hour';
    case 'DAILY':
      return 'day';
    case 'WEEKLY':
      return 'week';
    case 'PER_JOB':
      return 'job';
    default:
      return 'month';
  }
}

final hiringCatalogProvider = FutureProvider<HiringCatalog>((ref) async {
  try {
    final data = await ref.read(matchingRepositoryProvider).catalog();
    return HiringCatalog.fromJson(data);
  } catch (_) {
    return HiringCatalog.fallback;
  }
});
