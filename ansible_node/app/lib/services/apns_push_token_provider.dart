import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'push_registration_service.dart';

/// [PushTokenProvider] backed by native APNS via the `elix/push_token`
/// method channel (ios/Runner/AppDelegate.swift). Content-free wakes need no
/// user alert permission — only `registerForRemoteNotifications()` plus the
/// `remote-notification` background mode and `aps-environment` entitlement.
///
/// Returns null (push unavailable) on Android — the FCM provider lands with
/// the Android release work — and on simulators, registration failures, or
/// timeouts, matching the [PushTokenProvider] contract so registration stays
/// visibly "not configured" rather than silently broken.
class ApnsPushTokenProvider implements PushTokenProvider {
  ApnsPushTokenProvider({
    @visibleForTesting MethodChannel? channel,
    @visibleForTesting bool Function()? isIos,
    this.timeout = const Duration(seconds: 8),
  }) : _channel = channel ?? const MethodChannel('elix/push_token'),
       _isIos = isIos ?? (() => Platform.isIOS);

  final MethodChannel _channel;
  final bool Function() _isIos;

  /// APNS registration normally answers in well under a second; the timeout
  /// covers a hung registration (e.g. no network to Apple) so the settings
  /// toggle can report "unavailable" instead of spinning forever.
  final Duration timeout;

  @override
  Future<PushDeviceToken?> currentToken() async {
    if (!_isIos()) return null;
    try {
      final token = await _channel
          .invokeMethod<String>('requestToken')
          .timeout(timeout);
      if (token == null || token.isEmpty) return null;
      return PushDeviceToken(token: token, platform: 'apns');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// Registers a callback for content-free wake pushes forwarded by the
  /// native side while the engine is alive. The callback should run a bounded
  /// sync pass; it must never assume any notification content.
  void onWake(Future<void> Function() handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'wakeReceived') {
        await handler();
      }
      return null;
    });
  }
}
