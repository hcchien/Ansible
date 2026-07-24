import 'package:ansible_node/services/platform_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile security capabilities stay explicit', () {
    final ios = PlatformCapabilities.forPlatform(ElixPlatform.ios);
    final android = PlatformCapabilities.forPlatform(ElixPlatform.android);

    expect(ios.hardwareIdentityKey, isTrue);
    expect(ios.passportNfc, isTrue);
    expect(ios.pushWake, isTrue);
    expect(android.hardwareIdentityKey, isTrue);
    expect(android.mobileMoica, isTrue);
    expect(android.passportNfc, isFalse);
    expect(android.pushWake, isFalse);
  });

  test('macOS uses Secure Enclave and desktop-only local AI', () {
    final macos = PlatformCapabilities.forPlatform(ElixPlatform.macos);

    expect(macos.desktop, isTrue);
    expect(macos.hardwareIdentityKey, isTrue);
    expect(macos.webAuthn, isTrue);
    expect(macos.localAiAccess, isTrue);
    expect(macos.bundledLocalAiHelper, isTrue);
    expect(macos.passportNfc, isFalse);
  });

  test('Windows and Linux never pretend software keys are hardware custody', () {
    final windows = PlatformCapabilities.forPlatform(ElixPlatform.windows);
    final linux = PlatformCapabilities.forPlatform(ElixPlatform.linux);

    expect(windows.reducedTrustIdentityOnly, isTrue);
    expect(windows.webAuthn, isTrue);
    expect(linux.reducedTrustIdentityOnly, isTrue);
    expect(linux.webAuthn, isFalse);
    expect(windows.localAiAccess, isTrue);
    expect(linux.localAiAccess, isTrue);
  });

  test('web exposes WebAuthn but no native device capabilities', () {
    final web = PlatformCapabilities.forPlatform(
      ElixPlatform.macos,
      isWeb: true,
    );

    expect(web.platform, ElixPlatform.web);
    expect(web.webAuthn, isTrue);
    expect(web.hardwareIdentityKey, isFalse);
    expect(web.localAiAccess, isFalse);
  });
}
