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

  group('firstNonEmptyPhoto', () {
    test('skips null and blank talent photoUrl and uses the account avatar', () {
      expect(
        firstNonEmptyPhoto([null, '', '  ', '/uploads/me.jpg']),
        '/uploads/me.jpg',
      );
    });

    test('prefers an existing talent photo over the account avatar', () {
      expect(
        firstNonEmptyPhoto(['/uploads/pro.jpg', '/uploads/me.jpg']),
        '/uploads/pro.jpg',
      );
    });
  });

  group('registerProPhotoHint', () {
    test('does not ask to upload again when a photo is already set', () {
      expect(
        registerProPhotoHint('/uploads/me.jpg'),
        'This is your profile photo. Tap to change it.',
      );
      expect(
        registerProPhotoHint(null),
        'Tap to upload a profile photo',
      );
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

  group('encodeWhatsAppPhotoJpeg', () {
    test('keeps aspect ratio and caps the long edge at 1600', () {
      final src = img.Image(width: 2400, height: 1600);
      img.fill(src, color: img.ColorRgb8(40, 120, 200));
      final bytes = Uint8List.fromList(img.encodePng(src));

      final decoded = img.decodeJpg(encodeWhatsAppPhotoJpeg(bytes))!;
      expect(decoded.width, kPhotoMaxEdge);
      expect(decoded.height, 1067);
    });

    test('does not upscale a smaller photo', () {
      final src = img.Image(width: 800, height: 600);
      img.fill(src, color: img.ColorRgb8(20, 80, 40));
      final bytes = Uint8List.fromList(img.encodePng(src));

      final decoded = img.decodeJpg(encodeWhatsAppPhotoJpeg(bytes))!;
      expect(decoded.width, 800);
      expect(decoded.height, 600);
    });

    test('caps a tall portrait on height', () {
      final src = img.Image(width: 1200, height: 2400);
      img.fill(src, color: img.ColorRgb8(180, 90, 20));
      final bytes = Uint8List.fromList(img.encodePng(src));

      final decoded = img.decodeJpg(encodeWhatsAppPhotoJpeg(bytes))!;
      expect(decoded.width, 800);
      expect(decoded.height, kPhotoMaxEdge);
    });
  });
}
