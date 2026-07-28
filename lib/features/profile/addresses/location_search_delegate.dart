import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';
import '../../../theme.dart';

class OlaPlace {
  final String description;
  final double lat;
  final double lng;

  const OlaPlace({
    required this.description,
    required this.lat,
    required this.lng,
  });

  factory OlaPlace.fromJson(Map<String, dynamic> json) {
    final geom = json['geometry']?['location'] ?? {};
    return OlaPlace(
      description: json['description']?.toString() ?? 'Unknown Location',
      lat: double.tryParse('${geom['lat'] ?? 0.0}') ?? 0.0,
      lng: double.tryParse('${geom['lng'] ?? 0.0}') ?? 0.0,
    );
  }
}

class LocationSearchDelegate extends SearchDelegate<OlaPlace?> {
  final Dio _dio = Dio();

  @override
  String get searchFieldLabel => 'Search area or address...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSuggestionsList();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Search for a location',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return _buildSuggestionsList();
  }

  Widget _buildSuggestionsList() {
    return FutureBuilder<List<OlaPlace>>(
      future: _searchPlaces(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading results.',
              style: TextStyle(color: context.gx.ink.withValues(alpha: 0.5)),
            ),
          );
        }

        final places = snapshot.data ?? [];

        if (places.isEmpty) {
          return Center(
            child: Text(
              'No results found.',
              style: TextStyle(color: context.gx.ink.withValues(alpha: 0.5)),
            ),
          );
        }

        return ListView.separated(
          itemCount: places.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
          itemBuilder: (context, index) {
            final place = places[index];
            return ListTile(
              leading: Icon(Icons.location_on, color: context.gx.accent),
              title: Text(place.description),
              onTap: () {
                close(context, place);
              },
            );
          },
        );
      },
    );
  }

  Future<List<OlaPlace>> _searchPlaces(String input) async {
    final key = AppConfig.olaMapsApiKey;
    if (key.isEmpty || input.trim().isEmpty) return [];

    try {
      final response = await _dio.get(
        'https://api.olamaps.io/places/v1/autocomplete',
        queryParameters: {
          'input': input.trim(),
          'api_key': key,
        },
      );

      final predictions = response.data['predictions'] as List?;
      if (predictions == null) return [];

      return predictions
          .whereType<Map<String, dynamic>>()
          .map((e) => OlaPlace.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('Ola places search error: $e');
      return [];
    }
  }
}
