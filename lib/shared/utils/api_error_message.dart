import 'package:dio/dio.dart';

/// Maps Dio / API failures to short user-facing copy.
/// Never returns raw `DioException` / `SocketException` dumps.
String apiErrorMessage(
  Object error, {
  String fallback =
      'Please check your network or try again later.',
}) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Check your internet and try again.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        final msg = error.message ?? error.error?.toString() ?? '';
        if (msg.contains('SocketException') ||
            msg.contains('Network is unreachable') ||
            msg.contains('Connection failed') ||
            msg.contains('Failed host lookup')) {
          return 'No internet connection. Check your network and try again.';
        }
        if (error.type == DioExceptionType.connectionError) {
          return 'No internet connection. Check your network and try again.';
        }
        break;
      default:
        break;
    }

    final data = error.response?.data;
    if (data is Map) {
      final raw = data['message'];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      if (raw is List && raw.isNotEmpty) {
        final first = raw.first?.toString().trim() ?? '';
        if (first.isNotEmpty) return first;
      }
    }
    return fallback;
  }

  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('Network is unreachable') ||
      text.contains('Connection failed')) {
    return 'No internet connection. Check your network and try again.';
  }
  return fallback;
}
