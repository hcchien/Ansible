import 'package:flutter/foundation.dart';

enum ElixPlatform { ios, android, macos, windows, linux, web, unknown }

/// Central source of truth for native capabilities.
///
/// A feature must consult this contract before presenting an action that
/// depends on a platform channel. Unsupported security features fail closed;
/// reduced-trust identity is always explicitly labelled and user-confirmed.
class PlatformCapabilities {
  const PlatformCapabilities({
    required this.platform,
    required this.hardwareIdentityKey,
    required this.webAuthn,
    required this.passportNfc,
    required this.mobileMoica,
    required this.cameraScanner,
    required this.pushWake,
    required this.localAiAccess,
    required this.bundledLocalAiHelper,
    required this.appLinks,
  });

  final ElixPlatform platform;
  final bool hardwareIdentityKey;
  final bool webAuthn;
  final bool passportNfc;
  final bool mobileMoica;
  final bool cameraScanner;
  final bool pushWake;
  final bool localAiAccess;
  final bool bundledLocalAiHelper;
  final bool appLinks;

  bool get desktop => switch (platform) {
    ElixPlatform.macos || ElixPlatform.windows || ElixPlatform.linux => true,
    _ => false,
  };

  bool get reducedTrustIdentityOnly =>
      platform == ElixPlatform.windows || platform == ElixPlatform.linux;

  static PlatformCapabilities get current =>
      forPlatform(_currentPlatform(), isWeb: kIsWeb);

  static PlatformCapabilities forPlatform(
    ElixPlatform platform, {
    bool isWeb = false,
  }) {
    if (isWeb || platform == ElixPlatform.web) {
      return const PlatformCapabilities(
        platform: ElixPlatform.web,
        hardwareIdentityKey: false,
        webAuthn: true,
        passportNfc: false,
        mobileMoica: false,
        cameraScanner: false,
        pushWake: false,
        localAiAccess: false,
        bundledLocalAiHelper: false,
        appLinks: false,
      );
    }

    return switch (platform) {
      ElixPlatform.ios => const PlatformCapabilities(
        platform: ElixPlatform.ios,
        hardwareIdentityKey: true,
        webAuthn: true,
        passportNfc: true,
        mobileMoica: true,
        cameraScanner: true,
        pushWake: true,
        localAiAccess: false,
        bundledLocalAiHelper: false,
        appLinks: true,
      ),
      ElixPlatform.android => const PlatformCapabilities(
        platform: ElixPlatform.android,
        hardwareIdentityKey: true,
        webAuthn: true,
        // Kept off until the native reader and the Android-native ZK prover
        // ship together. Never expose a reader-only personhood flow.
        passportNfc: false,
        mobileMoica: true,
        cameraScanner: true,
        pushWake: false,
        localAiAccess: false,
        bundledLocalAiHelper: false,
        appLinks: true,
      ),
      ElixPlatform.macos => const PlatformCapabilities(
        platform: ElixPlatform.macos,
        hardwareIdentityKey: true,
        webAuthn: true,
        passportNfc: false,
        mobileMoica: false,
        cameraScanner: true,
        pushWake: false,
        localAiAccess: true,
        bundledLocalAiHelper: true,
        appLinks: true,
      ),
      ElixPlatform.windows => const PlatformCapabilities(
        platform: ElixPlatform.windows,
        hardwareIdentityKey: false,
        webAuthn: true,
        passportNfc: false,
        mobileMoica: false,
        cameraScanner: false,
        pushWake: false,
        localAiAccess: true,
        bundledLocalAiHelper: false,
        appLinks: true,
      ),
      ElixPlatform.linux => const PlatformCapabilities(
        platform: ElixPlatform.linux,
        hardwareIdentityKey: false,
        webAuthn: false,
        passportNfc: false,
        mobileMoica: false,
        cameraScanner: false,
        pushWake: false,
        localAiAccess: true,
        bundledLocalAiHelper: false,
        appLinks: false,
      ),
      ElixPlatform.unknown => const PlatformCapabilities(
        platform: ElixPlatform.unknown,
        hardwareIdentityKey: false,
        webAuthn: false,
        passportNfc: false,
        mobileMoica: false,
        cameraScanner: false,
        pushWake: false,
        localAiAccess: false,
        bundledLocalAiHelper: false,
        appLinks: false,
      ),
      ElixPlatform.web => throw StateError('handled above'),
    };
  }

  static ElixPlatform _currentPlatform() {
    if (kIsWeb) return ElixPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => ElixPlatform.ios,
      TargetPlatform.android => ElixPlatform.android,
      TargetPlatform.macOS => ElixPlatform.macos,
      TargetPlatform.windows => ElixPlatform.windows,
      TargetPlatform.linux => ElixPlatform.linux,
      TargetPlatform.fuchsia => ElixPlatform.unknown,
    };
  }
}
