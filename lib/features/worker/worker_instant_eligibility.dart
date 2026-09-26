import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart' show Ref;

import '../../repositories/auth_repository.dart';
import '../../repositories/worker_repository.dart';
import 'worker_live_presence.dart';

/// Go-Live dashboard: skills + per-service activation + earnings summary.
/// `GET /workers/me/dashboard` — refreshed after every live toggle.
final goLiveDashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    return ref.watch(workerRepositoryProvider).getGoLiveDashboard();
  },
  retry: (retryCount, error) {
    if (retryCount >= 2) return null;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return Duration(milliseconds: 300 * (retryCount + 1));
        default:
          return null;
      }
    }
    return null;
  },
);

/// Whether the bottom-nav availability control should show.
///
/// Matches `canAcceptInstantJobs` from the server when present: registered
/// pro who meets go-online gates (verified, languages, credits, not
/// suspended), or already online (so they can go offline).
bool shouldShowAvailabilityControl(Map<String, dynamic> dash) {
  if (dash['isActive'] == true) return true;
  final flag = dash['canAcceptInstantJobs'];
  if (flag is bool) return flag;
  return _clientFallbackShowAvailabilityControl(dash);
}

/// Client fallback when the dashboard predates `canAcceptInstantJobs`.
bool _clientFallbackShowAvailabilityControl(Map<String, dynamic> dash) {
  final skills = (dash['skills'] as List?)?.whereType<String>().toList() ?? [];
  final verStatus = (dash['verificationStatus'] as String?) ?? 'PENDING';
  if (skills.isEmpty && verStatus == 'PENDING') return false;
  if (skills.isEmpty) return false;
  if (dash['suspended'] == true) return false;
  final strikes = (dash['strikeCount'] as num?)?.toInt() ?? 0;
  if (strikes >= 3) return false;
  if (verStatus != 'VERIFIED') return false;
  final langs = (dash['languages'] as List?)?.whereType<String>().toList() ?? [];
  if (langs.isEmpty) return false;
  final credits = (dash['jobCredits'] as num?)?.toInt() ?? 0;
  return credits > 0;
}

/// Shell-level dashboard fetch — keepAlive so bottom-nav eligibility survives
/// tab switches. `null` = not a registered pro (404).
final workerShellDashboardProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.keepAlive();
  final hasToken = await ref.read(authTokenServiceProvider).hasToken();
  if (!hasToken) return null;
  try {
    return await ref.read(workerRepositoryProvider).getGoLiveDashboard();
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
});

/// Whether the center availability control should show. Hidden while loading,
/// on error, for customers, and for ineligible pros.
final workerShowAvailabilityControlProvider = Provider<bool>((ref) {
  final dashAsync = ref.watch(workerShellDashboardProvider);
  return dashAsync.maybeWhen(
    data: (dash) => dash != null && shouldShowAvailabilityControl(dash),
    orElse: () => false,
  );
});

typedef _RiverpodRead = T Function<T>(ProviderListenable<T> provider);
typedef _RiverpodInvalidate = void Function(ProviderOrFamily provider);

void _syncWorkerLiveFromDashboardCore(
  _RiverpodRead read,
  Map<String, dynamic>? dash,
) {
  if (dash == null || !dash.containsKey('isActive')) return;
  final serverLive = dash['isActive'] == true;
  read(workerLiveStateProvider.notifier).state = serverLive;
  final presence = read(workerLivePresenceProvider);
  if (serverLive) {
    unawaited(presence.start());
  } else {
    presence.stop();
  }
}

void _clearWorkerAvailabilitySessionStateCore(
  _RiverpodRead read,
  _RiverpodInvalidate invalidate,
) {
  read(workerLiveStateProvider.notifier).state = false;
  read(workerSpokenLanguagesProvider.notifier).state = null;
  read(workerLiveToggleBusyProvider.notifier).state = false;
  read(workerLivePresenceProvider).stop();
  invalidate(workerShellDashboardProvider);
  invalidate(goLiveDashboardProvider);
}

void syncWorkerLiveFromDashboard(Ref ref, Map<String, dynamic>? dash) {
  _syncWorkerLiveFromDashboardCore(ref.read, dash);
}

void syncWorkerLiveFromDashboardWidget(
  WidgetRef ref,
  Map<String, dynamic>? dash,
) {
  _syncWorkerLiveFromDashboardCore(ref.read, dash);
}

void clearWorkerAvailabilitySessionState(Ref ref) {
  _clearWorkerAvailabilitySessionStateCore(ref.read, ref.invalidate);
}

void clearWorkerAvailabilitySessionStateWidget(WidgetRef ref) {
  _clearWorkerAvailabilitySessionStateCore(ref.read, ref.invalidate);
}

Future<void> refreshWorkerAvailabilityFromServer(Ref ref) async {
  ref.invalidate(workerShellDashboardProvider);
  try {
    final dash = await ref.read(workerShellDashboardProvider.future);
    _syncWorkerLiveFromDashboardCore(ref.read, dash);
    final presence = ref.read(workerLivePresenceProvider);
    if (dash != null && dash['isActive'] == true) {
      await presence.start();
    } else {
      presence.stop();
    }
  } catch (_) {}
}

Future<void> refreshWorkerAvailabilityFromServerWidget(WidgetRef ref) async {
  ref.invalidate(workerShellDashboardProvider);
  try {
    final dash = await ref.read(workerShellDashboardProvider.future);
    _syncWorkerLiveFromDashboardCore(ref.read, dash);
    final presence = ref.read(workerLivePresenceProvider);
    if (dash != null && dash['isActive'] == true) {
      await presence.start();
    } else {
      presence.stop();
    }
  } catch (_) {}
}
