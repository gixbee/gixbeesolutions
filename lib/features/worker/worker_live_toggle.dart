import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/worker_repository.dart';
import '../../services/location_service.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'worker_instant_eligibility.dart';
import 'worker_live_presence.dart';

List<String> parseSpokenLanguages(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Toggles online/offline via `POST /workers/live-toggle`. Updates
/// [workerLiveStateProvider] only after server confirmation.
Future<void> runWorkerLiveToggle(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? dashboard,
  GlobalKey? scrollToLanguagesKey,
}) async {
  if (ref.read(workerLiveToggleBusyProvider)) return;
  ref.read(workerLiveToggleBusyProvider.notifier).state = true;
  final currentlyLive = ref.read(workerLiveStateProvider);
  final wantLive = !currentlyLive;
  try {
    double? lat;
    double? lng;
    final dash = dashboard ??
        ref.read(workerShellDashboardProvider).asData?.value ??
        ref.read(goLiveDashboardProvider).asData?.value;

    if (wantLive) {
      var langs = ref.read(workerSpokenLanguagesProvider);
      if (langs == null) {
        try {
          final me =
              await ref.read(workerRepositoryProvider).getMyWorkerProfile();
          langs = parseSpokenLanguages(me['languages']);
          ref.read(workerSpokenLanguagesProvider.notifier).state = langs;
        } catch (_) {
          langs = dash == null ? null : parseSpokenLanguages(dash['languages']);
          if (langs != null && langs.isEmpty) langs = null;
        }
      }
      if (langs != null && langs.isEmpty) {
        if (context.mounted) {
          showGxSnack(
            context,
            'Select at least one language you speak before going live.',
            type: GxSnackType.error,
          );
          final ctx = scrollToLanguagesKey?.currentContext;
          if (ctx != null && ctx.mounted) {
            await Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 280),
              alignment: 0.12,
            );
          }
        }
        return;
      }

      if (dash != null) {
        final credits = (dash['jobCredits'] as num?)?.toInt() ?? 0;
        if (credits <= 0) {
          if (context.mounted) {
            showGxSnack(
              context,
              'You need job credits to accept new bookings. Buy a pack now.',
              type: GxSnackType.error,
            );
          }
          return;
        }
      }

      final pos = await ref
          .read(locationServiceProvider)
          .getCurrentPosition();
      if (pos == null) {
        if (context.mounted) {
          // Release busy before the sheet — retry runs after the first call
          // finishes; otherwise the nested toggle no-ops on the busy guard.
          ref.read(workerLiveToggleBusyProvider.notifier).state = false;
          await showWorkerGpsRequiredSheet(context, ref, onRetryToggle: () {
            Future.microtask(() {
              unawaited(runWorkerLiveToggle(
                context,
                ref,
                dashboard: dashboard,
                scrollToLanguagesKey: scrollToLanguagesKey,
              ));
            });
          });
        }
        return;
      }
      lat = pos.latitude;
      lng = pos.longitude;
    }

    final result = await ref.read(workerRepositoryProvider).goLiveToggle(
          lat: lat,
          lng: lng,
          active: wantLive,
        );
    ref.read(workerLiveStateProvider.notifier).state = result.isActive;
    ref.invalidate(workerShellDashboardProvider);
    ref.invalidate(goLiveDashboardProvider);

    final presence = ref.read(workerLivePresenceProvider);
    if (result.isActive) {
      await presence.start();
    } else {
      presence.stop();
    }

    if (context.mounted) {
      showGxSnack(
        context,
        result.message,
        type: GxSnackType.success,
      );
    }
  } on DioException catch (e) {
    await resyncWorkerLiveAfterToggleFailure(ref);
    if (!context.mounted) return;
    if (ref.read(workerLiveStateProvider) == wantLive) {
      showGxSnack(
        context,
        wantLive
            ? 'You are now LIVE on the map and accepting jobs.'
            : 'You are now OFFLINE. Customers cannot dispatch you instantly.',
        type: GxSnackType.success,
      );
      return;
    }
    showGxSnack(context, workerLiveToggleErrorMessage(e), type: GxSnackType.error);
  } catch (_) {
    await resyncWorkerLiveAfterToggleFailure(ref);
    if (!context.mounted) return;
    if (ref.read(workerLiveStateProvider) == wantLive) {
      showGxSnack(
        context,
        wantLive
            ? 'You are now LIVE on the map and accepting jobs.'
            : 'You are now OFFLINE. Customers cannot dispatch you instantly.',
        type: GxSnackType.success,
      );
      return;
    }
    showGxSnack(
      context,
      'Could not update availability. Please try again.',
      type: GxSnackType.error,
    );
  } finally {
    ref.read(workerLiveToggleBusyProvider.notifier).state = false;
  }
}

Future<void> resyncWorkerLiveAfterToggleFailure(WidgetRef ref) async {
  try {
    final dash =
        await ref.read(workerRepositoryProvider).getGoLiveDashboard();
    ref.invalidate(workerShellDashboardProvider);
    ref.invalidate(goLiveDashboardProvider);
    syncWorkerLiveFromDashboardWidget(ref, dash);
    final presence = ref.read(workerLivePresenceProvider);
    if (dash['isActive'] == true) {
      await presence.start();
    } else {
      presence.stop();
    }
  } catch (_) {}
}

String workerLiveToggleErrorMessage(DioException e) {
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return 'Network timed out while updating availability. Check your connection and try again.';
  }
  if (e.type == DioExceptionType.connectionError) {
    return 'No network connection. Check your signal and try again.';
  }
  final data = e.response?.data;
  if (data is Map && data['message'] != null) {
    final m = data['message'];
    if (m is List && m.isNotEmpty) return m.first.toString();
    return m.toString();
  }
  return 'Could not update availability. Please try again.';
}

Future<void> showWorkerGpsRequiredSheet(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onRetryToggle,
}) async {
  final reason = await ref.read(locationServiceProvider).gpsBlockReason();
  if (!context.mounted) return;
  final isServiceOff = reason == 'service_off';
  final isDeniedForever = reason == 'denied_forever';
  await showGxSheet<void>(
    context,
    title: 'Location needed to go online',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Customers are matched to pros by live location. Without GPS you '
          'would appear online but never receive a single job — so going '
          'online stays off until location is available.',
          style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: context.gx.ink.withValues(alpha: 0.65)),
        ),
        const SizedBox(height: 16),
        if (isServiceOff || isDeniedForever)
          GxButton(
            label: isServiceOff
                ? 'Turn on device location'
                : 'Open app settings',
            icon: Icons.settings_rounded,
            onTap: () {
              final svc = ref.read(locationServiceProvider);
              if (isServiceOff) {
                svc.openLocationSettings();
              } else {
                svc.openAppSettings();
              }
              Navigator.pop(context);
            },
          )
        else
          GxButton(
            label: 'Allow location & go online',
            icon: Icons.my_location_rounded,
            onTap: () {
              Navigator.pop(context);
              onRetryToggle();
            },
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
}
