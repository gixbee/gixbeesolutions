import 'package:flutter/material.dart';

class WorkerReelsScreen extends StatefulWidget {
  final String name;
  final String role;
  final String image;

  const WorkerReelsScreen({
    super.key,
    required this.name,
    required this.role,
    required this.image,
  });

  @override
  State<WorkerReelsScreen> createState() => _WorkerReelsScreenState();
}

class _WorkerReelsScreenState extends State<WorkerReelsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image (Full Screen)
          Image.network(
            widget.image,
            fit: BoxFit.cover,
          ),

          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
          ),

          // Progress Bar (Mock)
          Positioned(
            top: 50,
            left: 10,
            right: 10,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content Info
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: NetworkImage(widget.image),
                      radius: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Follow',
                          style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Hi! I am specialized in ${widget.role}. Check out my recent work portfolio below 👇 #gixbee #${widget.role.toLowerCase()}',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('Book Now'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Close Button
          Positioned(
            top: 60,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Side Actions
          const Positioned(
            bottom: 100,
            right: 10,
            child: Column(
              children: [
                _ReelAction(icon: Icons.favorite, label: '4.2k'),
                SizedBox(height: 20),
                _ReelAction(icon: Icons.comment, label: '128'),
                SizedBox(height: 20),
                _ReelAction(icon: Icons.share, label: 'Share'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelAction extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ReelAction({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 30),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
