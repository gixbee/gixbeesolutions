import 'package:flutter/material.dart';
import 'plugin_registry.dart';
import '../config/app_strings.dart';

class JobsPlugin extends GixbeePlugin {
  @override
  String get id => 'jobs';
  @override
  String get name => 'Jobs';
  @override
  String get description => AppStrings.jobsPluginDescription;
  @override
  IconData get icon => Icons.work;
  
  bool _enabled = true;
  @override
  bool get isEnabled => _enabled;
  @override
  void toggle(bool value) => _enabled = value;

  @override
  Widget buildWidget(BuildContext context) {
    return const Center(child: Text('Jobs Plugin Content'));
  }
}

class RentalsPlugin extends GixbeePlugin {
  @override
  String get id => 'rentals';
  @override
  String get name => 'Rentals';
  @override
  String get description => AppStrings.rentalsPluginDescription;
  @override
  IconData get icon => Icons.car_rental;
  
  bool _enabled = true;
  @override
  bool get isEnabled => _enabled;
  @override
  void toggle(bool value) => _enabled = value;

  @override
  Widget buildWidget(BuildContext context) {
    return const Center(child: Text('Rentals Plugin Content'));
  }
}

void registerDefaultPlugins() {
  PluginRegistry.register(JobsPlugin());
  PluginRegistry.register(RentalsPlugin());
}
