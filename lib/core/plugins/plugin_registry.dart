import 'package:flutter/material.dart';

abstract class GixbeePlugin {
  String get id;
  String get name;
  String get description;
  IconData get icon;
  
  bool get isEnabled;
  void toggle(bool value);

  Widget buildWidget(BuildContext context);
}

class PluginRegistry {
  static final Map<String, GixbeePlugin> _plugins = {};

  static void register(GixbeePlugin plugin) {
    _plugins[plugin.id] = plugin;
  }

  static List<GixbeePlugin> get all => _plugins.values.toList();
  
  static List<GixbeePlugin> get enabled => 
      _plugins.values.where((p) => p.isEnabled).toList();

  static GixbeePlugin? getById(String id) => _plugins[id];
}
