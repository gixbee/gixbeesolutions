import 'package:flutter_riverpod/legacy.dart';

/// Bottom-nav tab index owned by [MainWrapper].
/// 0 Home · 1 Activity · 2 Messages · 3 Profile
///
/// Used so Profile (tab root) can "go back" to Home without calling
/// [Navigator.pop] on the shell — that incorrectly pops MainWrapper and
/// leaves a full black screen.
final mainTabIndexProvider = StateProvider<int>((ref) => 0);
