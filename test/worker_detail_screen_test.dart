// Gixbee 2026 — composed-screen widget test (Pass 128).
//
// Extends the ProviderScope-override seam proven in Passes 117–127 to the last
// named uncovered composed screen: `WorkerDetailScreen` (search → tap-a-pro
// detail page reached from the worker list). Unlike the loading/data/error
// screens covered earlier, this one is a `StatelessWidget` that renders a
// `Worker` model passed to its constructor directly — so there is no async
// main-content branch to drive; the tests assert the composed profile UI
// against a seeded `Worker`.
//
// TWO seams are handled:
//
// 1. FAVOURITES (Riverpod). The header `_FavouriteButton`
//    (`ConsumerStatefulWidget`) reads `favouritesRepositoryProvider
//    .isFavourite(id)` in `initState`. We override that provider with a
//    `_FakeFavRepo extends FavouritesRepository` (`super(Dio())`, unused) that
//    resolves `isFavourite` synchronously to a fixed `initial` — no mock
//    package, no Dio call, no network.
//
// 2. NETWORK IMAGE (the reason Pass 127 deferred this screen). The SliverAppBar
//    background is a raw `Image.network(worker.imageUrl)` with NO errorBuilder.
//    Under the flutter_test harness the binding's mock `HttpClient` returns 400,
//    and its response completes via microtasks that DO run during `pump()`, so
//    `NetworkImage._loadAsync` reaches the status check and throws
//    `NetworkImageLoadException` — an uncaught test exception. To neutralise it
//    we install a hand-rolled `HttpOverrides` (`_MockImageHttpOverrides`) in
//    `setUpAll` whose client returns a 200 response streaming a valid 1×1
//    transparent PNG. The 400-throw path is thus replaced by a well-formed
//    response; the subsequent image *decode* is an engine callback that does not
//    progress under FakeAsync (we never call `runAsync`), so the image simply
//    stays pending — harmless, and no test asserts the pixels. `HttpOverrides`
//    is restored in `tearDownAll`. `imageUrl` uses the reserved `.invalid` TLD
//    regardless.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/search/worker_detail_screen.dart';
import 'package:gixbee/repositories/favourites_repository.dart';
import 'package:gixbee/shared/models/worker.dart';

// ---------------------------------------------------------------------------
// Network-image mock (self-contained; no external package).
// ---------------------------------------------------------------------------

/// A valid 1×1 fully-transparent PNG (the well-known `transparent_image`
/// bytes). Decodes cleanly if the engine ever runs; we only need the HTTP layer
/// to answer 200 with well-formed bytes so `NetworkImage` does not throw.
final Uint8List _kTransparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

class _MockImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockHttpClientRequest();

  // autoUncompress setter etc. are swallowed harmlessly.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _kTransparentPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_kTransparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ---------------------------------------------------------------------------
// Fakes + fixtures.
// ---------------------------------------------------------------------------

/// A [FavouritesRepository] that never touches the network. `isFavourite`
/// resolves to a fixed [initial] on a microtask (no timer, no Dio), so the
/// `_FavouriteButton.initState` load completes cleanly under the harness.
/// `add`/`remove` are unused by these tests (no tap fires them).
class _FakeFavRepo extends FavouritesRepository {
  final bool initial;
  _FakeFavRepo({this.initial = false}) : super(Dio());

  @override
  Future<bool> isFavourite(String workerId) async => initial;
}

/// Builds a fully-populated [Worker] with overridable fields, shaped like the
/// objects the app yields from `Worker.fromMap`.
Worker _worker({
  String id = 'w_0001',
  String name = 'Asha Kumar',
  String title = 'Master Electrician',
  String bio = 'Fifteen years wiring homes across the city.',
  double rating = 4.7,
  int reviewCount = 18,
  double hourlyRate = 300,
  List<String> skills = const ['Electrician', 'Wiring'],
  List<String> availabilityTags = const ['Weekdays'],
  String status = 'available',
  double? distanceKm,
}) =>
    Worker(
      id: id,
      name: name,
      title: title,
      bio: bio,
      imageUrl: 'https://example.invalid/$id.jpg',
      rating: rating,
      completedJobs: 42,
      reviewCount: reviewCount,
      isFeatured: false,
      hourlyRate: hourlyRate,
      skills: skills,
      availabilityTags: availabilityTags,
      primaryType: SkillType.manual,
      status: status,
      distanceKm: distanceKm,
    );

/// Hosts [WorkerDetailScreen] under a `ProviderScope` whose
/// `favouritesRepositoryProvider` is a no-network fake. A plain dark
/// [ThemeData] is used (not `GixbeeTheme`) so `Theme.of(context)` resolves
/// without pulling in google_fonts' runtime font fetch.
Widget _host(
  Worker worker, {
  bool isInstant = true,
  bool favInitial = false,
}) =>
    ProviderScope(
      overrides: [
        favouritesRepositoryProvider
            .overrideWithValue(_FakeFavRepo(initial: favInitial)),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: WorkerDetailScreen(worker: worker, isInstant: isInstant),
      ),
    );

void main() {
  HttpOverrides? previous;

  setUpAll(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = _MockImageHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = previous;
  });

  group('WorkerDetailScreen', () {
    // Two bounded frames: build + the `_FavouriteButton` initState microtask.
    // Kept off `pumpAndSettle`, consistent with the sibling suites.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    // Each test sets a phone viewport so the fixed bottom-sheet CTA row and the
    // tall SliverAppBar lay out without a RenderFlex overflow on the default
    // 800x600 test surface.
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('renders the worker profile fields', (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(_worker()));
      await settle(tester);

      expect(find.text('Asha Kumar'), findsOneWidget);
      expect(find.text('Master Electrician'), findsOneWidget);
      // Rating (headline uses rating.toString()) + review count.
      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('18 reviews'), findsOneWidget);
      // Pricing: '₹300' + 'per hour'.
      expect(find.text('₹300'), findsOneWidget);
      expect(find.text('per hour'), findsOneWidget);
      // Bio section.
      expect(find.text('About this Professional'), findsOneWidget);
      expect(find.text('Fifteen years wiring homes across the city.'),
          findsOneWidget);
      // Skills section header + a skill chip (exact match — 'Electrician' does
      // not collide with the 'Master Electrician' title under find.text).
      expect(find.text('Skills & Expertise'), findsOneWidget);
      expect(find.text('Electrician'), findsOneWidget);
      // Availability tag chip.
      expect(find.text('Weekdays'), findsOneWidget);
    });

    testWidgets('available worker → shows Book Now + Chat Now CTAs',
        (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(_worker(status: 'available')));
      await settle(tester);

      expect(find.text('Chat Now'), findsOneWidget);
      expect(find.text('Book Now'), findsOneWidget);
      expect(find.text('Worker is Busy'), findsNothing);
    });

    testWidgets('busy worker → shows the disabled Worker is Busy CTA',
        (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(_worker(status: 'busy')));
      await settle(tester);

      expect(find.text('Worker is Busy'), findsOneWidget);
      expect(find.text('Book Now'), findsNothing);
      // Chat is still offered regardless of availability.
      expect(find.text('Chat Now'), findsOneWidget);
    });

    testWidgets('distanceKm present → renders the "km away" line',
        (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(_worker(distanceKm: 2.5)));
      await settle(tester);

      expect(find.text('2.5 km away'), findsOneWidget);
    });

    testWidgets('distanceKm null → hides the "km away" line', (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(_worker(distanceKm: null)));
      await settle(tester);

      expect(find.textContaining('km away'), findsNothing);
    });

    testWidgets('favourite = false → header shows the "Save" heart',
        (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(_worker(), favInitial: false));
      await settle(tester);

      expect(find.byTooltip('Save to favourites'), findsOneWidget);
      expect(find.byTooltip('Remove from favourites'), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      // Share action is always present in the header.
      expect(find.byTooltip('Share'), findsOneWidget);
    });

    testWidgets('favourite = true → header shows the "Remove" heart',
        (tester) async {
      phone(tester);
      await tester.pumpWidget(_host(_worker(), favInitial: true));
      await settle(tester);

      expect(find.byTooltip('Remove from favourites'), findsOneWidget);
      expect(find.byTooltip('Save to favourites'), findsNothing);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });
  });
}
