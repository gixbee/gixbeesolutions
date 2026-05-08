import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/debug_log_service.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/glass_container.dart';
import '../../repositories/auth_repository.dart';

class DebugLogScreen extends ConsumerWidget {
  const DebugLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(debugLogProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('System Logs'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => ref.read(debugLogProvider.notifier).clear(),
          ),
        ],
      ),
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ── FCM Diagnostic Buttons ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _DiagButton(
                        icon: Icons.health_and_safety,
                        label: 'FCM Health',
                        color: Colors.blue,
                        onTap: () => _checkFcmHealth(context, ref),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DiagButton(
                        icon: Icons.notifications_active,
                        label: 'Test Push',
                        color: Colors.green,
                        onTap: () => _sendTestPush(context, ref),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Log List ────────────────────────────────────────
              Expanded(
                child: logs.isEmpty
                    ? const Center(
                        child: Text(
                          'No logs captured yet.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(24),
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final log = logs[logs.length - 1 - index];
                          return GlassContainer(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              log,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkFcmHealth(BuildContext context, WidgetRef ref) async {
    final logger = ref.read(debugLogProvider.notifier);
    logger.log('[DIAG] Checking FCM health...');
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/notifications/health');
      final data = response.data as Map<String, dynamic>;
      final initialized = data['firebaseInitialized'] ?? false;
      final creds = data['credentials'] ?? {};

      logger.log('[DIAG] Firebase initialized: $initialized');
      logger.log('[DIAG] Has ProjectId: ${creds['hasProjectId']}');
      logger.log('[DIAG] Has ClientEmail: ${creds['hasClientEmail']}');
      logger.log('[DIAG] Has PrivateKey: ${creds['hasPrivateKey']}');
      logger.log('[DIAG] ProjectId: ${creds['projectId']}');
      logger.log('[DIAG] Firebase apps: ${data['firebaseAppsCount']}');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(initialized
                ? '✅ Firebase is initialized'
                : '❌ Firebase NOT initialized — check server .env'),
            backgroundColor: initialized ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      logger.log('[DIAG] Health check failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Health check failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendTestPush(BuildContext context, WidgetRef ref) async {
    final logger = ref.read(debugLogProvider.notifier);
    logger.log('[DIAG] Sending test push to self...');
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post('/notifications/test-self');
      final data = response.data as Map<String, dynamic>;
      final success = data['success'] ?? false;
      final steps = data['steps'] as List<dynamic>? ?? [];

      // Log each diagnostic step
      for (final step in steps) {
        logger.log('[DIAG] $step');
      }
      logger.log('[DIAG] Result: ${data['message']}');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? '✅ Push sent! Check your notification tray.'
                : '❌ ${data['message']}'),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      logger.log('[DIAG] Test push failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test push failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _DiagButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DiagButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
