import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/business/hiring_application_status_screen.dart';
import 'package:gixbee/features/business/hiring_application_submitted_screen.dart';
import 'package:gixbee/features/business/hiring_business_verification_screen.dart';
import 'package:gixbee/features/business/hiring_employer_type_screen.dart';
import 'package:gixbee/features/business/hiring_listing.dart';
import 'package:gixbee/features/business/list_business_type_screen.dart';
import 'package:gixbee/shared/models/business.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: child,
    );

Business _hiringBiz({
  String status = 'PENDING',
  Map<String, dynamic>? hiringProfile,
  String? documentUrl,
}) =>
    Business(
      id: 'biz_1',
      name: 'Acme Staffing',
      type: 'HIRING',
      ownerId: 'owner_1',
      status: status,
      documentUrl: documentUrl,
      hiringProfile: hiringProfile,
    );

void main() {
  test('hiringOtpPhone normalises Indian mobiles', () {
    expect(hiringOtpPhone('9876543210'), '+919876543210');
    expect(hiringOtpPhone('+91 98765 43210'), '+919876543210');
  });

  test('sameHiringPhone matches last 10 digits', () {
    expect(sameHiringPhone('+919876543210', '9876543210'), isTrue);
    expect(sameHiringPhone('1111111111', '2222222222'), isFalse);
  });

  test('hiringDomainMatched requires the same non-consumer domain', () {
    expect(hiringDomainMatched('hr@acme.com', 'jobs@acme.com'), isTrue);
    expect(hiringDomainMatched('hr@gmail.com', 'jobs@gmail.com'), isFalse);
    expect(hiringDomainMatched('hr@acme.com', 'jobs@other.com'), isFalse);
    expect(hiringDomainMatched('not-an-email', 'jobs@acme.com'), isFalse);
  });

  test('HiringListingDraft profile json keeps employer kind and pin', () {
    final draft = HiringListingDraft(
      employerKind: HiringEmployerKind.staffing,
      industries: const ['Healthcare'],
      roleInBusiness: 'Recruiter',
      authorised: true,
      lat: 8.52,
      lng: 76.94,
      pinLabel: 'Technopark Phase 1',
      pinSub: 'Thiruvananthapuram, Kerala',
      otherDocumentType: 'Shop Act',
      documentName: 'shop-act.pdf',
    );
    final json = draft.toProfileJson();
    expect(json['employerKind'], 'STAFFING');
    expect(json['industries'], ['Healthcare']);
    expect(json['lat'], 8.52);
    expect(json['pinLabel'], 'Technopark Phase 1');
    expect(json['otherDocumentType'], 'Shop Act');
    expect(json['documentName'], 'shop-act.pdf');
    expect(json.containsKey('reviewNote'), isFalse);
  });

  test('fromBusiness rebuilds a resubmit draft and requires a fresh tick', () {
    final draft = HiringListingDraft.fromBusiness(_hiringBiz(
      status: 'NEEDS_CHANGES',
      documentUrl: '/uploads/gst.pdf',
      hiringProfile: {
        'employerKind': 'DIRECT',
        'industries': ['Retail'],
        'roleInBusiness': 'Owner',
        'registrationType': 'GST Certificate',
        'workEmail': 'hr@shop.com',
        'reviewNote': 'Business registration document is unclear.',
        'phoneVerified': true,
        'lat': 8.4,
        'lng': 76.9,
      },
    ));
    expect(draft.isResubmit, isTrue);
    expect(draft.employerKind, HiringEmployerKind.direct);
    expect(draft.roleInBusiness, 'Owner');
    expect(draft.registrationType, 'GST Certificate');
    expect(draft.documentUrl, '/uploads/gst.pdf');
    expect(draft.authorised, isFalse);
    expect(draft.reviewNote, 'Business registration document is unclear.');
  });

  testWidgets('List My Business shows Hiring Business, not Hiring Agency',
      (tester) async {
    await tester.pumpWidget(_host(const ListBusinessTypeScreen()));
    await tester.pump();
    expect(find.text('List My Business'), findsWidgets);
    expect(find.text('Hiring Business'), findsOneWidget);
    expect(find.text('Employers, Recruiters, Staffing Agencies'),
        findsOneWidget);
    expect(find.text('Hiring Agency'), findsNothing);
    expect(find.text('Service Business'), findsOneWidget);
    expect(find.text('Rental Business'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('employer type requires a selection before Continue',
      (tester) async {
    await tester.pumpWidget(_host(const HiringEmployerTypeScreen()));
    await tester.pump();
    expect(find.text('How do you hire?'), findsWidgets);
    expect(find.text('Direct Employer'), findsOneWidget);
    expect(find.text('Hiring employees for my own business'), findsOneWidget);
    expect(find.text('Recruitment / Staffing Agency'), findsOneWidget);
    expect(find.text('Staffing Agency'), findsNothing);
    expect(find.text('Hiring candidates for other businesses'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.byType(HiringEmployerTypeScreen), findsOneWidget);
  });

  testWidgets('under-review screen shows submitted status and Go to Home',
      (tester) async {
    await tester.pumpWidget(_host(const HiringApplicationSubmittedScreen()));
    await tester.pump();
    expect(find.text('Application Submitted'), findsOneWidget);
    expect(find.text("We're reviewing your business details."), findsOneWidget);
    expect(find.text('UNDER REVIEW'), findsOneWidget);
    expect(find.text("We'll notify you when verification is complete."),
        findsOneWidget);
    expect(find.text('Go to Home'), findsOneWidget);
    expect(find.text('View Application'), findsNothing);
  });

  testWidgets('submitted screen offers View Application when business is known',
      (tester) async {
    await tester.pumpWidget(
        _host(HiringApplicationSubmittedScreen(business: _hiringBiz())));
    await tester.pump();
    expect(find.text('View Application'), findsOneWidget);
  });

  testWidgets('verification screen is Step 3 and hides Business Verified',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: _host(HiringBusinessVerificationScreen(
        draft: HiringListingDraft(
          employerKind: HiringEmployerKind.direct,
          name: 'Acme',
          industries: const ['Retail'],
          phoneVerified: true,
          lat: 8.52,
          lng: 76.94,
        ),
      )),
    ));
    await tester.pump();
    expect(find.text('Verify Your Business'), findsOneWidget);
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('HIRING'), findsOneWidget);
    expect(find.text('Verify your business'), findsOneWidget);
    expect(find.text('YOUR ROLE'), findsOneWidget);
    expect(find.text('BUSINESS REGISTRATION'), findsOneWidget);
    expect(find.text('Upload Registration Document'), findsOneWidget);
    expect(find.text('JPG, PNG or PDF up to 5MB'), findsOneWidget);
    expect(find.text('WORK EMAIL'), findsOneWidget);
    expect(find.text('Verification Summary'), findsOneWidget);
    expect(find.text('Phone Verified'), findsOneWidget);
    expect(find.text('Business Details'), findsOneWidget);
    expect(find.text('Location Added'), findsOneWidget);
    expect(find.text('Registration Document'), findsOneWidget);
    expect(find.text('Business Verified'), findsNothing);
    expect(find.text('Business Verified ✓'), findsNothing);
    expect(find.text('Registration Number'), findsNothing);
    expect(find.text('Submit Application'), findsOneWidget);
    expect(
      find.text(
          'Your uploaded documents are used only for verification and are not shown publicly to candidates.'),
      findsOneWidget,
    );
  });

  testWidgets('needs-changes status shows requested edits and resubmit',
      (tester) async {
    await tester.pumpWidget(_host(HiringApplicationStatusScreen(
      business: _hiringBiz(
        status: 'NEEDS_CHANGES',
        hiringProfile: {
          'reviewNote': 'Business registration document is unclear.',
        },
      ),
    )));
    await tester.pump();
    expect(find.text('Verification Needs Changes'), findsOneWidget);
    expect(find.text('Business registration document is unclear.'),
        findsOneWidget);
    expect(find.text('NEEDS CHANGES'), findsOneWidget);
    expect(find.text('Update & Resubmit'), findsOneWidget);
  });

  testWidgets('verified status unlocks the hiring dashboard', (tester) async {
    await tester.pumpWidget(_host(HiringApplicationStatusScreen(
      business: _hiringBiz(status: 'VERIFIED'),
    )));
    await tester.pump();
    expect(find.text('Business Verified ✓'), findsOneWidget);
    expect(find.text('Your business is now verified. You can start posting jobs.'),
        findsOneWidget);
    expect(find.text('Open Hiring Dashboard'), findsOneWidget);
  });
}
