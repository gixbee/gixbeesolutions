import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import 'gx_button.dart';

/// WhatsApp-style square crop: pinch/pan the photo inside a fixed circle, then Use.
class GxProfilePhotoCropScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const GxProfilePhotoCropScreen({super.key, required this.imageBytes});

  @override
  State<GxProfilePhotoCropScreen> createState() =>
      _GxProfilePhotoCropScreenState();
}

class _GxProfilePhotoCropScreenState extends State<GxProfilePhotoCropScreen> {
  final _controller = CropController();
  bool _ready = false;
  bool _cropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Move and scale'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.imageBytes,
              controller: _controller,
              aspectRatio: 1,
              withCircleUi: true,
              interactive: true,
              fixCropRect: true,
              cornerDotBuilder: (_, __) => const SizedBox.shrink(),
              baseColor: Colors.black,
              maskColor: Colors.black.withValues(alpha: 0.55),
              progressIndicator: const Center(
                child: CircularProgressIndicator(
                  color: GixbeeTheme.accentGold,
                  strokeWidth: 2,
                ),
              ),
              onStatusChanged: (status) {
                if (status == CropStatus.ready && !_ready) {
                  setState(() => _ready = true);
                }
                if (status == CropStatus.cropping) {
                  setState(() => _cropping = true);
                }
              },
              onCropped: (data) {
                if (mounted) Navigator.pop(context, data);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: GxButton(
                label: 'Use photo',
                icon: Icons.check_rounded,
                loading: _cropping,
                onTap: !_ready || _cropping
                    ? null
                    : () {
                        setState(() => _cropping = true);
                        _controller.crop();
                      },
                gradient: GixbeeTheme.brandGradient,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
