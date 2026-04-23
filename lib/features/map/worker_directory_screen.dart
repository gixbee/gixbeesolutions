import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/models/worker.dart';
import '../../repositories/worker_repository.dart';
import '../../services/socket_service.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/glass_container.dart';
import '../profile/worker_profile_card.dart';

class WorkerDirectoryScreen extends ConsumerStatefulWidget {
  final String? jobId;

  const WorkerDirectoryScreen({super.key, this.jobId});

  @override
  ConsumerState<WorkerDirectoryScreen> createState() => _WorkerDirectoryScreenState();
}

class _WorkerDirectoryScreenState extends ConsumerState<WorkerDirectoryScreen> {
  Position? _currentPosition;
  final Map<String, _LocationData> _liveLocations = {};
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _determinePosition();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final socketService = ref.read(socketServiceProvider);
      if (widget.jobId != null) {
        socketService.joinJobRoom(widget.jobId!);
      }

      socketService.onLocationUpdated((data) {
        if (mounted) {
          final String workerId = data['userId'];
          final double lat = (data['lat'] as num).toDouble();
          final double lng = (data['lng'] as num).toDouble();

          setState(() {
            _liveLocations[workerId] = _LocationData(lat, lng);
          });
        }
      });
    });
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        ),
      );
      
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _launchMaps(double lat, double lng) async {
    final String googleMapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final Uri uri = Uri.parse(googleMapsUrl);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps application.')),
        );
      }
    }
  }

  double? _calculateDistance(Worker worker) {
    if (_currentPosition == null) return null;
    
    // Check live location first, fallback to base worker location (if they had one)
    final loc = _liveLocations[worker.id];
    if (loc == null) return null; // We don't have a location for this worker yet

    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      loc.lat,
      loc.lng,
    );
  }

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(workersProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.jobId != null ? 'Worker Status' : 'Nearby Professionals',
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              setState(() => _isLoadingLocation = true);
              _determinePosition();
            },
          )
        ],
      ),
      body: DribbbleBackground(
        child: SafeArea(
          child: workersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (workers) {
          if (_isLoadingLocation) {
            return const Center(child: CircularProgressIndicator());
          }

          // If looking for a specific job worker
          if (widget.jobId != null) {
            final targetWorker = workers.firstWhere(
              (w) => w.id == widget.jobId, 
              orElse: () => workers.first
            );
            return _buildWorkerList([targetWorker]);
          }

          // Filter out workers without location and sort by distance
          final validWorkers = workers.where((w) => _liveLocations.containsKey(w.id)).toList();
          
          if (_currentPosition != null) {
            validWorkers.sort((a, b) {
              final distA = _calculateDistance(a) ?? double.infinity;
              final distB = _calculateDistance(b) ?? double.infinity;
              return distA.compareTo(distB);
            });
          }

          if (validWorkers.isEmpty) {
            return const Center(
              child: Text('Waiting for worker locations...'),
            );
          }

          return _buildWorkerList(validWorkers);
        },
      ),
    ),
  ),
);
}

  Widget _buildWorkerList(List<Worker> workers) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: workers.length,
      itemBuilder: (context, index) {
        final worker = workers[index];
        final distance = _calculateDistance(worker);
        
        String distanceStr = 'Unknown distance';
        if (distance != null) {
          if (distance < 1000) {
            distanceStr = '${distance.toStringAsFixed(0)}m away';
          } else {
            distanceStr = '${(distance / 1000).toStringAsFixed(1)}km away';
          }
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GlassContainer(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                radius: 30,
                backgroundImage: NetworkImage(worker.imageUrl),
              ),
            title: Text(
              worker.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(worker.title),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                     Text(
                      distanceStr,
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.directions),
              color: Theme.of(context).colorScheme.primary,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              ),
              onPressed: () {
                final loc = _liveLocations[worker.id];
                if (loc != null) {
                  _launchMaps(loc.lat, loc.lng);
                }
              },
            ),
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => WorkerProfileCard(worker: worker),
              );
            },
            ),
          ),
        );
      },
    );
  }
}

class _LocationData {
  final double lat;
  final double lng;
  _LocationData(this.lat, this.lng);
}
