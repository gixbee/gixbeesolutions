import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'hall_business_home_screen.dart';
import 'hall_setup_screen.dart';

/// Opens hall setup or hall home depending on venue.hallSetupComplete.
Future<void> openHallOwnerFlow(
  BuildContext context,
  WidgetRef ref,
  Business business,
) async {
  try {
    final venue =
        await ref.read(hallRepositoryProvider).getVenue(business.id);
    if (!context.mounted) return;
    final complete = venue['hallSetupComplete'] == true;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => complete
            ? HallBusinessHomeScreen(business: business)
            : HallSetupScreen(business: business),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    showGxSnack(context, 'Could not open halls: $e', type: GxSnackType.error);
  }
}
