import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../widgets/gx_profile_photo_crop.dart';
import '../widgets/gx_sheet.dart';
import '../../theme.dart';

/// WhatsApp-style profile photo output size (square JPEG).
const kProfilePhotoSize = 640;

/// Small list thumbnail; generated locally, not stored separately yet.
const kProfilePhotoThumbSize = 128;

/// JPEG quality after crop — visually sharp at 640px, far smaller than camera originals.
const kProfileJpegQuality = 85;

/// Pick at 1080 so the cropper has extra pixels, then downscale to 640.
const kProfilePickMax = 1080;

/// Center-crop to square if needed, resize to at most [kProfilePhotoSize], JPEG [kProfileJpegQuality].
/// Does not upscale a smaller crop.
Uint8List encodeWhatsAppProfileJpeg(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) return input;
  var src = decoded;
  if (src.width != src.height) {
    final side = math.min(src.width, src.height);
    final x = ((src.width - side) / 2).floor();
    final y = ((src.height - side) / 2).floor();
    src = img.copyCrop(src, x: x, y: y, width: side, height: side);
  }
  final side = math.min(kProfilePhotoSize, math.min(src.width, src.height));
  if (src.width != side || src.height != side) {
    src = img.copyResize(
      src,
      width: side,
      height: side,
      interpolation: img.Interpolation.cubic,
    );
  }
  return Uint8List.fromList(img.encodeJpg(src, quality: kProfileJpegQuality));
}

Uint8List encodeProfileThumb(Uint8List jpeg) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) return jpeg;
  final thumb = img.copyResize(
    decoded,
    width: kProfilePhotoThumbSize,
    height: kProfilePhotoThumbSize,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodeJpg(thumb, quality: 80));
}

Future<ImageSource?> choosePhotoSource(BuildContext context) {
  return showGxSheet<ImageSource>(
    context,
    title: 'Profile photo',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(Icons.photo_library_outlined, color: context.gx.ink),
          title: Text('Choose from gallery',
              style: TextStyle(color: context.gx.ink, fontWeight: FontWeight.w600)),
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
        ListTile(
          leading: Icon(Icons.photo_camera_outlined, color: context.gx.ink),
          title: Text('Take photo',
              style: TextStyle(color: context.gx.ink, fontWeight: FontWeight.w600)),
          onTap: () => Navigator.pop(context, ImageSource.camera),
        ),
      ],
    ),
  );
}

/// Gallery/camera → square crop (circle mask) → 640×640 JPEG q85.
Future<Uint8List?> pickWhatsAppProfilePhoto(BuildContext context) async {
  final source = await choosePhotoSource(context);
  if (source == null || !context.mounted) return null;
  final x = await ImagePicker().pickImage(
    source: source,
    maxWidth: kProfilePickMax.toDouble(),
    maxHeight: kProfilePickMax.toDouble(),
    imageQuality: 95,
  );
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  if (!context.mounted) return null;
  final cropped = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => GxProfilePhotoCropScreen(imageBytes: bytes),
    ),
  );
  if (cropped == null) return null;
  return encodeWhatsAppProfileJpeg(cropped);
}
