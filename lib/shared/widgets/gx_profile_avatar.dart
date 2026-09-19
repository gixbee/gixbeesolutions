import 'package:flutter/material.dart';

import '../media/profile_photo.dart';
import '../../theme.dart';

/// Circle avatar: uploaded photo when [imageUrl] is set, otherwise name initial.
class GxProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final double? fontSize;
  final List<Color>? colors;

  const GxProfileAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 80,
    this.fontSize,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final url = resolveProfileImageUrl(imageUrl);
    final trimmed = name.trim();
    final initial =
        trimmed.isEmpty ? 'G' : trimmed.characters.first.toUpperCase();
    final gradient = colors ??
        [context.gx.accentSoft, const Color(0xFFEC4899)];
    final letterSize = fontSize ?? (size * 0.4);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: letterSize,
          fontWeight: FontWeight.w900,
          color: context.gx.onAccent,
        ),
      ),
    );
    if (url == null) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.gx.ink.withValues(alpha: 0.06),
            ),
            alignment: Alignment.center,
            child: SizedBox(
              width: size * 0.28,
              height: size * 0.28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: context.gx.accent,
              ),
            ),
          );
        },
      ),
    );
  }
}
