import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/debug_log_service.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/glass_container.dart';

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
                    final log = logs[logs.length - 1 - index]; // Show latest first
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
      ),
    );
  }
}
