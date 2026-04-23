import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../../repositories/auth_repository.dart'; // To get dioProvider
import '../../core/config/app_config.dart';

class BannerEntry {
  final String id;
  final String label;
  final String imageUrl;
  final String? targetUrl;

  BannerEntry({
    required this.id,
    required this.label,
    required this.imageUrl,
    this.targetUrl,
  });

  factory BannerEntry.fromMap(Map<String, dynamic> map) {
    return BannerEntry(
      id: map['id'],
      label: map['label'],
      imageUrl: map['value'],
      targetUrl: map['category'],
    );
  }
}

final bannersProvider = FutureProvider<List<BannerEntry>>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final response = await dio.get('/master-entries', queryParameters: {'type': 'BANNER', 'isActive': true});
    final data = response.data as List;
    final banners = data.map((item) => BannerEntry.fromMap(item as Map<String, dynamic>)).toList();
    
    if (banners.isEmpty) {
      return [
        BannerEntry(
          id: 'default-1',
          label: 'Welcome to Gixbee!',
          imageUrl: '/assets/images/placeholder.png', // This will fail image.network but errorBuilder will catch it
        ),
      ];
    }
    return banners;
  } catch (e) {
    debugPrint('Error fetching banners: $e');
    return [
      BannerEntry(
        id: 'default-error',
        label: 'Gixbee: The Skill Intelligence Network',
        imageUrl: '/error',
      ),
    ];
  }
});

class HomeCarousel extends ConsumerWidget {
  const HomeCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannersAsync = ref.watch(bannersProvider);

    return bannersAsync.when(
      loading: () => const _CarouselPlaceholder(),
      error: (err, stack) => const SizedBox.shrink(),
      data: (banners) {
        if (banners.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            CarouselSlider(
              options: CarouselOptions(
                height: 250.0,
                autoPlay: true,
                enlargeCenterPage: false,
                viewportFraction: 1.0,
                aspectRatio: 1.5,
                initialPage: 0,
                autoPlayInterval: const Duration(seconds: 6),
              ),
              items: banners.map((banner) {
                return Builder(
                  builder: (BuildContext context) {
                    return Container(
                      width: MediaQuery.of(context).size.width,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            banner.imageUrl.startsWith('/api') || banner.imageUrl.startsWith('/uploads') 
                              ? AppConfig.baseUrl + banner.imageUrl
                              : banner.imageUrl, // Handle full URLs or placeholders
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.blue[700]!, Colors.blue[400]!],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.flash_on, color: Colors.white, size: 50),
                                    const SizedBox(height: 10),
                                    Text(
                                      banner.label,
                                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Premium dark overlay at bottom for text readability
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.7),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Text(
                                banner.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

class _CarouselPlaceholder extends StatelessWidget {
  const _CarouselPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[200],
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}
