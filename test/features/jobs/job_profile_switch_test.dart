import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/jobs/hiring_catalog.dart';
import 'package:gixbee/features/jobs/job_types_screen.dart';
import 'package:gixbee/repositories/matching_repository.dart';
import 'package:gixbee/repositories/talent_repository.dart';

class ProfileMatchingRepository extends MatchingRepository {
  ProfileMatchingRepository() : super(Dio());
  final profiles = [
    {
      'id': 'developer',
      'jobType': 'Software Developer',
      'matchingPaused': false
    },
    {'id': 'teacher', 'jobType': 'Teacher', 'matchingPaused': false},
  ];
  final updates = <String>[];
  Completer<void>? pending;

  @override
  Future<List<Map<String, dynamic>>> listPreferences() async =>
      profiles.map((profile) => Map<String, dynamic>.from(profile)).toList();

  @override
  Future<Map<String, dynamic>> updatePreference(
      String id, Map<String, dynamic> body) async {
    updates.add(id);
    if (pending != null) await pending!.future;
    final profile = profiles.firstWhere((profile) => profile['id'] == id);
    profile['matchingPaused'] = body['matchingPaused'] as bool;
    return Map<String, dynamic>.from(profile);
  }
}

class ProfileTalentRepository extends TalentRepository {
  ProfileTalentRepository() : super(Dio());
  @override
  Future<Map<String, dynamic>> getProfile() async =>
      {'profileStatus': 'ACTIVE'};
}

void main() {
  testWidgets('profile switches persist independently and disable during save',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = ProfileMatchingRepository();
    Future<void> open() async {
      await tester.pumpWidget(ProviderScope(overrides: [
        matchingRepositoryProvider.overrideWithValue(repository),
        talentRepositoryProvider.overrideWithValue(ProfileTalentRepository()),
        hiringCatalogProvider
            .overrideWith((ref) async => HiringCatalog.fallback),
      ], child: const MaterialApp(home: Scaffold(body: JobTypesScreen()))));
      await tester.pumpAndSettle();
    }

    SwitchListTile tile(String id) => tester
        .widget<SwitchListTile>(find.byKey(ValueKey('job-profile-switch-$id')));
    await open();
    repository.pending = Completer<void>();
    tile('developer').onChanged!(false);
    await tester.pump();
    expect(tile('developer').onChanged, isNull);
    expect(tile('teacher').onChanged, isNotNull);
    repository.pending!.complete();
    await tester.pumpAndSettle();
    expect(tile('developer').value, isFalse);
    expect(tile('teacher').value, isTrue);
    expect(repository.updates, ['developer']);
    await tester.pumpWidget(const SizedBox.shrink());
    await open();
    expect(tile('developer').value, isFalse);
    expect(tile('teacher').value, isTrue);
    repository.pending = null;
    tile('developer').onChanged!(true);
    await tester.pumpAndSettle();
    expect(tile('developer').value, isTrue);
    expect(tile('teacher').value, isTrue);
    repository.pending = Completer<void>();
    tile('developer').onChanged!(false);
    await tester.pump();
    repository.pending!.completeError(Exception('Save failed'));
    await tester.pumpAndSettle();
    expect(tile('developer').value, isTrue);
    expect(tile('developer').onChanged, isNotNull);
    expect(tile('teacher').value, isTrue);
  });
}
