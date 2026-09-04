import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ansible_node/services/apns_push_token_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('elix/push_token');

  Future<void> mockNative(Object? Function(MethodCall call) handler) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // These tests run on the host VM where Platform.isIOS is false, so they use
  // the injected channel and assert the channel-facing behavior; the iOS-only
  // guard is trivially data-driven.

  test('returns an apns token when the native side supplies one', () async {
    await mockNative((call) {
      expect(call.method, 'requestToken');
      return 'ab12cd34';
    });

    final provider = ApnsPushTokenProvider(channel: channel, isIos: () => true);
    final token = await provider.currentToken();
    expect(token, isNotNull);
    expect(token!.token, 'ab12cd34');
    expect(token.platform, 'apns');
  });

  test('returns null when registration is unavailable (nil token)', () async {
    await mockNative((_) => null);
    final provider = ApnsPushTokenProvider(channel: channel, isIos: () => true);
    expect(await provider.currentToken(), isNull);
  });

  test('returns null on platform errors instead of throwing', () async {
    await mockNative((_) => throw PlatformException(code: 'apns_failed'));
    final provider = ApnsPushTokenProvider(channel: channel, isIos: () => true);
    expect(await provider.currentToken(), isNull);
  });

  test(
    'returns null on timeout instead of hanging the settings toggle',
    () async {
      await mockNative(
        (_) async =>
            Future<String>.delayed(const Duration(seconds: 2), () => 'late'),
      );
      final provider = ApnsPushTokenProvider(
        channel: channel,
        isIos: () => true,
        timeout: const Duration(milliseconds: 50),
      );
      expect(await provider.currentToken(), isNull);
    },
  );

  test('wake callback fires on wakeReceived', () async {
    final provider = ApnsPushTokenProvider(channel: channel, isIos: () => true);
    var woke = 0;
    provider.onWake(() async => woke += 1);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('wakeReceived'),
          ),
          (_) {},
        );

    expect(woke, 1);
  });

  test('dispose stops forwarding wakeReceived', () async {
    final provider = ApnsPushTokenProvider(channel: channel, isIos: () => true);
    var woke = 0;
    provider.onWake(() async => woke += 1);
    provider.dispose();

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('wakeReceived'),
          ),
          (_) {},
        );

    expect(woke, 0);
  });
}
