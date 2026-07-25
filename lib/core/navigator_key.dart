import 'package:flutter/material.dart';

/// Global navigator key used to trigger navigation from outside widget trees,
/// such as automatically redirecting to the Welcome/Login screen when an HTTP 401
/// Unauthorized occurs and session token refresh fails.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
