import 'dart:math';
import 'package:flutter/material.dart';
import '../search/worker_list_screen.dart';

class SkillGraphScreen extends StatefulWidget {
  const SkillGraphScreen({super.key});

  @override
  State<SkillGraphScreen> createState() => _SkillGraphScreenState();
}

class _SkillGraphScreenState extends State<SkillGraphScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<SkillNode> _nodes = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _generateNodes();
  }

  void _generateNodes() {
    final rng = Random();
    for (int i = 0; i < 20; i++) {
      _nodes.add(
        SkillNode(
          id: i,
          x: rng.nextDouble() * 400 - 200,
          y: rng.nextDouble() * 600 - 300,
          label: _getSkillLabel(i),
          type: i % 3 == 0 ? NodeType.worker : NodeType.skill,
        ),
      );
    }
  }

  String _getSkillLabel(int i) {
    const skills = [
      'Plumbing',
      'Electrician',
      'Coding',
      'Driving',
      'Teaching',
      'Design',
      'Care',
      'Repair',
    ];
    return skills[i % skills.length];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Skill Graph'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _nodes.clear();
                _generateNodes();
              });
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: SkillGraphPainter(
              nodes: _nodes,
              animationValue: _controller.value,
              theme: Theme.of(context).colorScheme,
            ),
            child: Container(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const WorkerListScreen(),
            ),
          );
        },
        label: const Text('Find Talent'),
        icon: const Icon(Icons.search),
      ),
    );
  }
}

enum NodeType { skill, worker }

class SkillNode {
  final int id;
  double x;
  double y;
  final String label;
  final NodeType type;

  SkillNode({
    required this.id,
    required this.x,
    required this.y,
    required this.label,
    required this.type,
  });
}

class SkillGraphPainter extends CustomPainter {
  final List<SkillNode> nodes;
  final double animationValue;
  final ColorScheme theme;

  SkillGraphPainter({
    required this.nodes,
    required this.animationValue,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..strokeWidth = 1.0;

    // Draw Connections
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final nodeA = nodes[i];
        final nodeB = nodes[j];
        final dist =
            (Offset(nodeA.x, nodeA.y) - Offset(nodeB.x, nodeB.y)).distance;

        if (dist < 150) {
          final opacity = (1 - (dist / 150)).clamp(0.0, 1.0);
          paint.color = theme.secondary.withValues(alpha: opacity * 0.5);
          canvas.drawLine(
            center + Offset(nodeA.x, nodeA.y),
            center + Offset(nodeB.x, nodeB.y),
            paint,
          );
        }
      }
    }

    // Draw Nodes
    for (var node in nodes) {
      final offset = center + Offset(node.x, node.y);

      // Pulse effect
      final pulse = sin(animationValue * 2 * pi + node.id) * 0.5 + 0.5;

      paint.color =
          node.type == NodeType.worker ? theme.primary : theme.secondary;

      canvas.drawCircle(offset, 6 + (pulse * 2), paint);

      // Text Label
      final textSpan = TextSpan(
        text: node.label,
        style: TextStyle(
            color: theme.onSurface.withValues(alpha: 0.8), fontSize: 10),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, offset + const Offset(10, -5));
    }
  }

  @override
  bool shouldRepaint(covariant SkillGraphPainter oldDelegate) => true;
}
