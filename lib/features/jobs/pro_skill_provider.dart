import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/auth_repository.dart'; // for dioProvider
import 'pro_skill_taxonomy.dart';

/// Provider to fetch dynamic Pro Trades from the backend.
final proTradesProvider =
    FutureProvider.autoDispose<List<ProTrade>>((ref) async {
  // AUDIT FIX: this near-static admin taxonomy was re-downloaded on every
  // screen open. keepAlive caches the result; the timer expires it after
  // 10 minutes so admin edits still show up without an app restart.
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(timer.cancel);

  final dio = ref.watch(dioProvider);
  
  try {
    final response = await dio.get('/master-entries', queryParameters: {
      'type': 'PRO_TRADE',
      'isActive': 'true'
    });
    
    final data = response.data as List;
    
    // Map the JSON response to ProTrade objects
    final trades = data.map((item) {
      final label = item['label'] as String? ?? 'Unknown Trade';
      
      // Attempt to map string icon name to IconData
      // We fall back to a generic icon if not found
      IconData iconData = Icons.handyman_rounded;
      final iconStr = item['icon'] as String?;
      if (iconStr != null) {
        iconData = _getIconDataFromString(iconStr);
      }
      
      // Parse the comma-separated sub-skills
      final valueStr = item['value'] as String? ?? '';
      final subSkills = valueStr
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
          
      return ProTrade(label, iconData, subSkills);
    }).toList();
    
    return trades;
  } catch (e) {
    debugPrint('Failed to fetch dynamic trades: $e');
    // Fallback to the hardcoded list on network error
    return kProTrades;
  }
});

/// Helper to map string icon names from the database to actual Flutter icons.
IconData _getIconDataFromString(String iconName) {
  switch (iconName) {
    case 'bolt_rounded':
      return Icons.bolt_rounded;
    case 'plumbing_rounded':
      return Icons.plumbing_rounded;
    case 'directions_car_rounded':
      return Icons.directions_car_rounded;
    case 'cleaning_services_rounded':
      return Icons.cleaning_services_rounded;
    case 'medical_services_rounded':
      return Icons.medical_services_rounded;
    case 'handyman_rounded':
      return Icons.handyman_rounded;
    case 'ac_unit_rounded':
      return Icons.ac_unit_rounded;
    default:
      return Icons.handyman_rounded;
  }
}

/// Provider to lazily fetch sub-skills for a specific trade.
final subSkillsProvider = FutureProvider.family<List<String>, String>((ref, tradeName) async {
  final dio = ref.watch(dioProvider);
  try {
    final response = await dio.get('/master-entries', queryParameters: {
      'type': 'PRO_SUB_SKILL',
      'category': tradeName,
      'isActive': 'true'
    });
    
    final data = response.data as List;
    return data.map((item) => (item['label'] as String? ?? '').trim()).where((s) => s.isNotEmpty).toList();
  } catch (e) {
    debugPrint('Failed to fetch sub-skills for $tradeName: $e');
    return [];
  }
});
