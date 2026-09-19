import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/shared/media/profile_photo.dart';
import 'package:image/image.dart' as img;

void main() {
  group('resolveProfileImageUrl', () {
    test('returns null for empty paths', () {
      expect(resolveProfileImageUrl(null), isNull);
      expect(resolveProfileImageUrl(''), isNull);
      expect(resolveProfileImageUrl('   '), isNull);
    });

    test('keeps absolute http(s) URLs', () {
      expect(
        resolveProfileImageUrl('https://cdn.example/a.jpg'),
        'https://cdn.example/a.jpg',
      );
    });

    test('prefixes relative upload paths with API base', () {
      final url = resolveProfileImageUrl('/uploads/abc.jpg');
      expect(url, isNotNull);
      expect(url!.endsWith('/uploads/abc.jpg'), isTrue);
      expect(url.startsWith('http'), isTrue);
    });
  });

  group('encodeWhatsAppProfileJpeg', () {
    test('center-crops a rectangle and resizes to 640 square JPEG', () {
      final src = img.Image(width: 1200, height: 800);
      img.fill(src, color: img.ColorRgb8(200, 40, 40));
      final bytes = Uint8List.fromList(img.encodePng(src));

      final out = encodeWhatsAppProfileJpeg(bytes);
      final decoded = img.decodeJpg(out);
      expect(decoded, isNotNull);
      expect(decoded!.width, kProfilePhotoSize);
      expect(decoded.height, kProfilePhotoSize);
    });

    test('does not upscale a smaller square', () {
      final src = img.Image(width: 320, height: 320);
      img.fill(src, color: img.ColorRgb8(10, 120, 80));
      final bytes = Uint8List.fromList(img.encodePng(src));

      final out = encodeWhatsAppProfileJpeg(bytes);
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 320);
      expect(decoded.height, 320);
    });

    test('thumbnail is 128 square', () {
      final src = img.Image(width: 640, height: 640);
      img.fill(src, color: img.ColorRgb8(30, 30, 180));
      final jpeg =
          Uint8List.fromList(img.encodeJpg(src, quality: kProfileJpegQuality));
      final thumb = encodeProfileThumb(jpeg);
      final decoded = img.decodeJpg(thumb)!;
      expect(decoded.width, kProfilePhotoThumbSize);
      expect(decoded.height, kProfilePhotoThumbSize);
    });
  });
}
