import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final debugLogProvider = StateNotifierProvider<DebugLogNotifier, List<String>>((ref) {
  return DebugLogNotifier();
});

class DebugLogNotifier extends StateNotifier<List<String>> {
  DebugLogNotifier() : super([]);

  void log(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    state = [...state, '[$timestamp] $message'];
    
    // Keep only the last 100 logs to prevent memory bloat
    if (state.length > 100) {
      state = state.sublist(state.length - 100);
    }
  }

  void clear() {
    state = [];
  }
}
