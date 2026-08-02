import 'package:flutter/material.dart';

import '../../theme.dart';

Color liveTrackingStatusColor(String status) {
  switch (status) {
    case 'ARRIVED':
      return GixbeeTheme.accentGreen;
    case 'ACTIVE':
    case 'IN_PROGRESS':
      return GixbeeTheme.accentGold;
    case 'ACCEPTED':
    default:
      return GixbeeTheme.accentBlue;
  }
}

IconData liveTrackingStatusIcon(String status) {
  switch (status) {
    case 'ARRIVED':
      return Icons.place_rounded;
    case 'ACTIVE':
    case 'IN_PROGRESS':
      return Icons.build_rounded;
    case 'ACCEPTED':
    default:
      return Icons.directions_car_rounded;
  }
}

String liveTrackingStatusText(String status) {
  switch (status) {
    case 'ARRIVED':
      return 'Worker has arrived';
    case 'ACTIVE':
    case 'IN_PROGRESS':
      return 'Work in progress';
    case 'ACCEPTED':
      return 'Worker is on the way';
    default:
      return 'Tracking';
  }
}
