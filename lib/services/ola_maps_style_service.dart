import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';

/// Builds a MapLibre style JSON for Ola Maps with `api_key` injected into
/// every tile / sprite / glyph URL.
///
/// Passing only `style.json?api_key=…` is not enough — MapLibre then fetches
/// sources, sprites and glyphs without the key, which yields a blank map.
class OlaMapsStyleService {
  OlaMapsStyleService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
            ));

  final Dio _dio;

  /// Process-wide cache so reopening the tracking screen does not re-fetch
  /// style + TileJSON (slow + flaky on weak networks → blank second open).
  static String? _cachedStyleJson;
  static String? _cachedForKey;

  /// Returns a style JSON string ready for [MapLibreMap.styleString], or null
  /// if the key is missing / the style cannot be loaded.
  Future<String?> buildStyleJson({bool forceRefresh = false}) async {
    final key = AppConfig.olaMapsApiKey;
    if (key.isEmpty) return null;

    if (!forceRefresh &&
        _cachedStyleJson != null &&
        _cachedForKey == key) {
      return _cachedStyleJson;
    }

    try {
      final styleRes = await _dio.get<dynamic>(AppConfig.olaStyleUrl);
      final style = Map<String, dynamic>.from(styleRes.data as Map);

      if (style['sprite'] is String) {
        style['sprite'] = _withApiKey(style['sprite'] as String, key);
      }
      if (style['glyphs'] is String) {
        style['glyphs'] = _withApiKey(style['glyphs'] as String, key);
      }

      final sources = style['sources'];
      if (sources is Map) {
        for (final entry in sources.entries) {
          final raw = entry.value;
          if (raw is! Map) continue;
          final src = Map<String, dynamic>.from(raw);
          await _hydrateSource(src, key);
          sources[entry.key] = src;
        }
      }

      final encoded = jsonEncode(style);
      _cachedStyleJson = encoded;
      _cachedForKey = key;
      return encoded;
    } catch (e) {
      debugPrint('[OlaMaps] Failed to build style JSON: $e');
      return _cachedStyleJson; // last good style if any
    }
  }

  Future<void> _hydrateSource(Map<String, dynamic> src, String key) async {
    final tiles = src['tiles'];
    if (tiles is List) {
      src['tiles'] = tiles.map((t) => _withApiKey(t.toString(), key)).toList();
      return;
    }

    final url = src['url']?.toString();
    if (url == null || url.isEmpty) return;

    try {
      final tjRes = await _dio.get<dynamic>(_withApiKey(url, key));
      final tj = Map<String, dynamic>.from(tjRes.data as Map);
      final tjTiles = tj['tiles'];
      if (tjTiles is List && tjTiles.isNotEmpty) {
        src.remove('url');
        src['tiles'] =
            tjTiles.map((t) => _withApiKey(t.toString(), key)).toList();
        for (final field in ['minzoom', 'maxzoom', 'bounds', 'attribution']) {
          if (tj[field] != null) src[field] = tj[field];
        }
        return;
      }
    } catch (e) {
      debugPrint('[OlaMaps] TileJSON hydrate failed for $url: $e');
    }

    src['url'] = _withApiKey(url, key);
  }

  static String _withApiKey(String url, String key) {
    if (url.contains('api_key=')) return url;
    return url.contains('?') ? '$url&api_key=$key' : '$url?api_key=$key';
  }
}

/// Coerce Nest Decimal / JSON number-or-string into a double.
double? readCoord(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
