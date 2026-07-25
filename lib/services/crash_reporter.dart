import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/config/app_config.dart';

/// Global error reporter that catches unhandled Flutter/Dart exceptions
/// and POSTs them to the backend's `/client-logs` endpoint.
///
/// The reports appear in the admin portal under System Logs → App Crashes.
///
/// Usage: Call [CrashReporter.init()] once in main() before runApp().
class CrashReporter {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  /// Device description, computed once on startup.
  static String get _device {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Initializes global error handlers:
  /// 1. FlutterError.onError — catches widget/rendering errors
  /// 2. PlatformDispatcher.instance.onError — catches async Dart errors
  static void init() {
    // 1. Synchronous Flutter framework errors (widget build, layout, paint).
    final defaultHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      // Still forward to the default handler (red screen in debug, silent in release).
      defaultHandler?.call(details);
      _report(
        error: details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
        errorType: 'FlutterError',
        screen: details.context?.toString(),
      );
    };

    // 2. Async Dart errors not caught by any Zone/try-catch.
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _report(
        error: error.toString(),
        stackTrace: stack.toString(),
        errorType: 'PlatformError',
      );
      // Return true to prevent the runtime from terminating the app.
      return true;
    };
  }

  /// Fire-and-forget POST to /client-logs. Never throws — crash reporting
  /// must never itself crash the app.
  static void _report({
    required String error,
    String? stackTrace,
    String? errorType,
    String? screen,
  }) {
    // In debug mode, don't spam the server with every hot-reload rebuild error.
    if (kDebugMode) {
      debugPrint('[CRASH_REPORTER] $errorType: $error');
      return;
    }

    try {
      _dio.post('/client-logs', data: {
        'error': error.length > 500 ? error.substring(0, 500) : error,
        if (stackTrace != null)
          'stackTrace': stackTrace.length > 8000
              ? stackTrace.substring(0, 8000)
              : stackTrace,
        if (errorType != null) 'errorType': errorType,
        if (screen != null)
          'screen': screen.length > 200 ? screen.substring(0, 200) : screen,
        'appVersion': AppConfig.buildVersion,
        'device': _device,
      });
    } catch (_) {
      // Swallow — crash reporting must never crash the app.
    }
  }
}
