// Gixbee 2026 — composed-screen widget test (Pass 129).
//
// `CandidateProfileScreen` is a plain `StatelessWidget` driven entirely by a
// single `JobApplication` prop (no repository, no Riverpod, no network), so —
// unlike the Pass 117–125 suites — it needs no `ProviderScope` override and no
// fake repository. Each test constructs a `JobApplication` fixture and pumps the
// screen, asserting the rendered content: the status pill (one branch of
// `_getStatusColor` per test), the applicant name, the cover-letter / job
// sections, and the null-fallback paths (missing name → "Unknown Candidate" +
// 'U' avatar initial; missing cover letter → the standard placeholder).
//
// No platform channels are touched at render: `url_launcher` (résumé) and
// `ChatThreadScreen` navigation are reached only from taps, which no test
// triggers. The screen is a `SingleChildScrollView`, which builds all children
// eagerly, so every text node is in the tree regardless of scroll offset — plain
// bounded `pump()`s suffice (no repeating animation to settle, so no
// `pumpAndSettle`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/business/candidate_profile_screen.dart';
import 'package:gixbee/shared/models/job_post.dart';

/// Builds a `JobApplication` fixture. Every field has a sensible default so each
/// test overrides only what it exercises.
JobApplication _application({
  String? applicantName = 'Bhavna Iyer',
  String applicantId = 'user-1',
  String? coverLetter = 'I have five years of on-site electrical experience.',
  String? resumeUrl,
  ApplicationStatus status = ApplicationStatus.applied,
  String jobTitle = 'Senior Electrician',
  String jobLocation = 'Pune, MH',
}) {
  return JobApplication(
    id: 'app-1',
    applicantId: applicantId,
    applicantName: applicantName,
    coverLetter: coverLetter,
    resumeUrl: resumeUrl,
    status: status,
    jobPost: JobPost(
      id: 'job-1',
      title: jobTitle,
      description: 'desc',
      requiredSkills: const ['Wiring'],
      jobType: 'Full Time',
      experience: 'Senior',
      location: jobLocation,
      isActive: true,
      employerId: 'emp-1',
    ),
  );
}

Widget _host(JobApplication application) => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: CandidateProfileScreen(application: application),
    );

void main() {
  group('CandidateProfileScreen', () {
    testWidgets('full application → name, status pill, cover letter, job & CTAs',
        (tester) async {
      await tester.pumpWidget(_host(_application(
        applicantName: 'Bhavna Iyer',
        status: ApplicationStatus.selected,
        coverLetter: 'I have five years of on-site electrical experience.',
        jobTitle: 'Senior Electrician',
        jobLocation: 'Pune, MH',
      )));
      await tester.pump();

      expect(find.text('Bhavna Iyer'), findsOneWidget);
      // status.name.toUpperCase() → 'SELECTED'.
      expect(find.text('SELECTED'), findsOneWidget);
      // Avatar initial = first letter of the name.
      expect(find.text('B'), findsOneWidget);
      expect(
          find.text('I have five years of on-site electrical experience.'),
          findsOneWidget);
      // "Applied For" section shows job title (content) + location (subtitle).
      expect(find.text('Senior Electrician'), findsOneWidget);
      expect(find.text('Pune, MH'), findsOneWidget);
      // Both action controls render.
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
    });

    testWidgets('null name & cover letter → fallbacks + "U" avatar initial',
        (tester) async {
      await tester.pumpWidget(_host(_application(
        applicantName: null,
        coverLetter: null,
      )));
      await tester.pump();

      expect(find.text('Unknown Candidate'), findsOneWidget);
      // applicantName == null → the avatar shows the 'U' placeholder initial.
      expect(find.text('U'), findsOneWidget);
      expect(
          find.text('No cover letter provided for this application.'),
          findsOneWidget);
    });

    testWidgets('interview status → renders the INTERVIEW pill', (tester) async {
      await tester.pumpWidget(
          _host(_application(status: ApplicationStatus.interview)));
      await tester.pump();

      expect(find.text('INTERVIEW'), findsOneWidget);
    });

    testWidgets('rejected status → renders the REJECTED pill', (tester) async {
      await tester.pumpWidget(
          _host(_application(status: ApplicationStatus.rejected)));
      await tester.pump();

      expect(find.text('REJECTED'), findsOneWidget);
    });

    testWidgets('chrome → AppBar title and section headers present',
        (tester) async {
      await tester.pumpWidget(_host(_application()));
      await tester.pump();

      expect(find.text('Candidate Profile'), findsOneWidget);
      expect(find.text('Cover Letter'), findsOneWidget);
      expect(find.text('Applied For'), findsOneWidget);
    });
  });
}
