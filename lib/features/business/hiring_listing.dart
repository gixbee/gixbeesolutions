import '../../shared/models/business.dart';

/// Hiring-business registration extras (Direct Employer vs Staffing Agency).
/// Persisted as `businesses.hiringProfile` jsonb — not job-post fields.
enum HiringEmployerKind { direct, staffing }

extension HiringEmployerKindX on HiringEmployerKind {
  String get apiValue =>
      this == HiringEmployerKind.direct ? 'DIRECT' : 'STAFFING';

  String get label => this == HiringEmployerKind.direct
      ? 'Direct Employer'
      : 'Staffing Agency';

  String get cardTitle => this == HiringEmployerKind.direct
      ? 'Direct Employer'
      : 'Recruitment / Staffing Agency';

  String get cardSubtitle => this == HiringEmployerKind.direct
      ? 'Hiring employees for my own business'
      : 'Hiring candidates for other businesses';

  String get detailsTitle => this == HiringEmployerKind.direct
      ? 'Registering as a Hiring Business'
      : 'Registering as a Staffing Agency';

  String get detailsSubtitle => this == HiringEmployerKind.direct
      ? 'Tell us about your company so we can verify and list your jobs.'
      : 'Tell us about your agency so we can verify and list you.';

  String get industryLabel => this == HiringEmployerKind.direct
      ? 'Industry *'
      : 'Industries You Hire For *';
}

const hiringIndustryOptions = [
  'IT & Software',
  'Healthcare',
  'Retail',
  'Hospitality',
  'Construction',
  'Logistics',
  'Events',
  'Education',
  'Manufacturing',
  'Other',
];

const hiringCompanySizes = [
  '1–10',
  '11–50',
  '51–200',
  '201–500',
  '500+',
];

const hiringRoles = [
  'Owner',
  'HR',
  'Manager',
  'Recruiter',
  'Authorised Representative',
];

const hiringRegistrationTypes = [
  'GST Certificate',
  'Udyam Registration',
  'CIN / Company Registration',
  'Business Licence',
  'Other',
];

const _consumerEmailDomains = {
  'gmail.com',
  'googlemail.com',
  'yahoo.com',
  'yahoo.co.in',
  'outlook.com',
  'hotmail.com',
  'live.com',
  'icloud.com',
  'rediffmail.com',
  'proton.me',
  'protonmail.com',
  'aol.com',
};

/// Draft carried List My Business → verification → POST / PATCH businesses.
class HiringListingDraft {
  HiringEmployerKind employerKind;
  String? existingBusinessId;
  String name;
  List<String> industries;
  String? companySize;
  String description;
  String? logoUrl;
  String phone;
  bool phoneVerified;
  String email;
  String address;
  String city;
  String? cityId;
  double? lat;
  double? lng;
  String? pinLabel;
  String? pinSub;
  String? roleInBusiness;
  String? registrationType;
  String registrationNumber;
  String otherDocumentType;
  String? documentUrl;
  String? documentName;
  String workEmail;
  bool authorised;
  String? reviewNote;

  HiringListingDraft({
    required this.employerKind,
    this.existingBusinessId,
    this.name = '',
    List<String>? industries,
    this.companySize,
    this.description = '',
    this.logoUrl,
    this.phone = '',
    this.phoneVerified = false,
    this.email = '',
    this.address = '',
    this.city = '',
    this.cityId,
    this.lat,
    this.lng,
    this.pinLabel,
    this.pinSub,
    this.roleInBusiness,
    this.registrationType,
    this.registrationNumber = '',
    this.otherDocumentType = '',
    this.documentUrl,
    this.documentName,
    this.workEmail = '',
    this.authorised = false,
    this.reviewNote,
  }) : industries = industries ?? [];

  bool get isResubmit =>
      existingBusinessId != null && existingBusinessId!.isNotEmpty;

  Map<String, dynamic> toProfileJson() => {
        'employerKind': employerKind.apiValue,
        'industries': industries,
        if (companySize != null && companySize!.isNotEmpty)
          'companySize': companySize,
        if (email.trim().isNotEmpty) 'email': email.trim(),
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (pinLabel != null) 'pinLabel': pinLabel,
        if (pinSub != null) 'pinSub': pinSub,
        'phoneVerified': phoneVerified,
        if (roleInBusiness != null) 'roleInBusiness': roleInBusiness,
        if (registrationType != null && registrationType!.isNotEmpty)
          'registrationType': registrationType,
        if (registrationNumber.trim().isNotEmpty)
          'registrationNumber': registrationNumber.trim(),
        if (otherDocumentType.trim().isNotEmpty)
          'otherDocumentType': otherDocumentType.trim(),
        if (documentName != null && documentName!.trim().isNotEmpty)
          'documentName': documentName!.trim(),
        if (workEmail.trim().isNotEmpty) 'workEmail': workEmail.trim(),
        'authorised': authorised,
      };

  static HiringListingDraft fromBusiness(Business b) {
    final p = b.hiringProfile ?? const <String, dynamic>{};
    final kind = p['employerKind']?.toString() == 'STAFFING'
        ? HiringEmployerKind.staffing
        : HiringEmployerKind.direct;
    List<String> industries = [];
    final raw = p['industries'];
    if (raw is List) {
      industries = raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if ((b.specialty ?? '').trim().isNotEmpty) {
      industries = b.specialty!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return HiringListingDraft(
      employerKind: kind,
      existingBusinessId: b.id,
      name: b.name,
      industries: industries,
      companySize: p['companySize']?.toString(),
      description: b.description ?? '',
      logoUrl: p['logoUrl']?.toString(),
      phone: b.phone ?? '',
      phoneVerified: p['phoneVerified'] == true,
      email: (p['email'] ?? '').toString(),
      address: b.address ?? '',
      cityId: b.cityId,
      lat: (p['lat'] as num?)?.toDouble(),
      lng: (p['lng'] as num?)?.toDouble(),
      pinLabel: p['pinLabel']?.toString(),
      pinSub: p['pinSub']?.toString(),
      roleInBusiness: p['roleInBusiness']?.toString(),
      registrationType: p['registrationType']?.toString(),
      registrationNumber: (p['registrationNumber'] ?? '').toString(),
      otherDocumentType: (p['otherDocumentType'] ?? '').toString(),
      documentUrl: b.documentUrl,
      documentName: p['documentName']?.toString(),
      workEmail: (p['workEmail'] ?? '').toString(),
      authorised: false,
      reviewNote: p['reviewNote']?.toString(),
    );
  }
}

String hiringOtpPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.length == 10) return '+91$digits';
  if (digits.length > 10) return '+$digits';
  return raw.trim();
}

bool sameHiringPhone(String a, String b) {
  String last10(String s) {
    final d = s.replaceAll(RegExp(r'\D'), '');
    return d.length >= 10 ? d.substring(d.length - 10) : d;
  }

  final x = last10(a);
  final y = last10(b);
  return x.isNotEmpty && x == y;
}

String? hiringEmailDomain(String email) {
  final trimmed = email.trim().toLowerCase();
  final at = trimmed.lastIndexOf('@');
  if (at <= 0 || at == trimmed.length - 1) return null;
  final domain = trimmed.substring(at + 1);
  if (!domain.contains('.') || domain.startsWith('.') || domain.endsWith('.')) {
    return null;
  }
  return domain;
}

/// True when the work email uses the same non-consumer domain as the
/// business email (company website / domain match).
bool hiringDomainMatched(String workEmail, String businessEmail) {
  final work = hiringEmailDomain(workEmail);
  final business = hiringEmailDomain(businessEmail);
  if (work == null || business == null) return false;
  if (_consumerEmailDomains.contains(work)) return false;
  return work == business;
}

String hiringReviewNote(Map<String, dynamic>? profile) {
  final note = profile?['reviewNote']?.toString().trim() ?? '';
  return note;
}

String hiringDocumentLabel(String? documentName, String? documentUrl) {
  final named = documentName?.trim() ?? '';
  if (named.isNotEmpty) return named;
  final url = documentUrl?.trim() ?? '';
  if (url.isEmpty) return 'Document';
  final slash = url.replaceAll('\\', '/').split('/').last;
  return slash.isEmpty ? 'Document' : slash;
}
