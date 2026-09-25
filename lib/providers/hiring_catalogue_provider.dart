import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/matching_repository.dart';
import '../services/app_data_cache.dart';

/// Server cache versions; refreshes on app resume and periodically while watched.
final serverCacheVersionsProvider = FutureProvider<Map<String, int>>((ref) async {
  final link = ref.keepAlive();

  void bump() => ref.invalidateSelf();

  final lifecycle = AppLifecycleListener(onResume: bump);
  final poll = Timer.periodic(const Duration(minutes: 15), (_) => bump());

  ref.onDispose(() {
    lifecycle.dispose();
    poll.cancel();
    link.close();
  });

  final repo = ref.watch(matchingRepositoryProvider);
  return repo.fetchCacheVersions();
});

/// Shared hiring catalogue snapshot (sectors, qualifications, languages, …).
final hiringCatalogueSnapshotProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final link = ref.keepAlive();
  Timer? expiry;

  void armExpiry() {
    expiry?.cancel();
    expiry = Timer(AppDataCache.hiringSnapshotTtl, () {
      AppDataCache.instance.clearHiringSnapshot();
      ref.invalidate(serverCacheVersionsProvider);
      ref.invalidateSelf();
      link.close();
    });
  }

  ref.onDispose(() => expiry?.cancel());

  // Re-run when server versions refresh (resume / poll / manual invalidation).
  final versions = await ref.watch(serverCacheVersionsProvider.future);
  final hiringV = versions['hiring_master'] ?? 0;
  AppDataCache.instance.setServerVersions(hiringMaster: hiringV);

  if (AppDataCache.instance.hiringSnapshotFresh(hiringV)) {
    armExpiry();
    return AppDataCache.instance.hiringSnapshotActive!;
  }

  final repo = ref.watch(matchingRepositoryProvider);
  final body = await repo.hiringCatalogue();
  final cacheVersion = (body['cacheVersion'] as num?)?.toInt() ?? hiringV;
  AppDataCache.instance.setServerVersions(hiringMaster: cacheVersion);
  AppDataCache.instance.putHiringSnapshot(body, cacheVersion);
  armExpiry();
  return body;
});
