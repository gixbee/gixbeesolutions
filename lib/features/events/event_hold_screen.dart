import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme.dart';
import 'event_plan_detail_screen.dart';

/// Twenty-minute hold after an event request, then the request details.
class EventHoldScreen extends StatefulWidget {
  const EventHoldScreen({super.key, required this.planId, required this.title});

  final String planId;
  final String title;

  @override
  State<EventHoldScreen> createState() => _EventHoldScreenState();
}

class _EventHoldScreenState extends State<EventHoldScreen> {
  static const _hold = Duration(minutes: 20);
  late final DateTime _until;
  Timer? _ticker;
  Duration _left = _hold;

  @override
  void initState() {
    super.initState();
    _until = DateTime.now().add(_hold);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _until.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _left = left.isNegative ? Duration.zero : left);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _clock {
    final minutes = _left.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _left.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(title: const Text('Slot hold')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text(
            'The provider has 20 minutes to confirm this request. The hold ends on its own if they do not reply.',
          ),
          const SizedBox(height: 24),
          Text(_clock,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: context.gx.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => EventPlanDetailScreen(planId: widget.planId),
              ),
            ),
            child: const Text('View request'),
          ),
        ],
      ),
    );
  }
}
