import 'package:ansible_node/services/sync_authorization_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reuses one authorization within the fixed foreground window', () async {
    var now = DateTime.utc(2026, 8, 20, 12);
    var authenticationCalls = 0;
    final sessions = <_FakeSession>[];
    final controller = SyncAuthorizationController(now: () => now);

    Future<SyncAuthenticationSession?> authenticate() async {
      authenticationCalls += 1;
      final session = _FakeSession();
      sessions.add(session);
      return session;
    }

    final first = await controller.acquire(
      scope: 'did:elix:alice',
      authenticate: authenticate,
    );
    expect(first, isNotNull);
    expect(first!.reuseHardwareAuthenticationContext, isTrue);
    await first.release();

    now = now.add(const Duration(seconds: 30));
    final second = await controller.acquire(
      scope: 'did:elix:alice',
      authenticate: authenticate,
    );
    await second!.release();

    expect(authenticationCalls, 1);
    expect(sessions.single.closeCalls, 0);
    await controller.invalidate();
    expect(sessions.single.closeCalls, 1);
  });

  test('use does not slide the sixty-second expiry', () async {
    var now = DateTime.utc(2026, 8, 20, 12);
    var authenticationCalls = 0;
    final sessions = <_FakeSession>[];
    final controller = SyncAuthorizationController(now: () => now);

    Future<SyncAuthenticationSession?> authenticate() async {
      authenticationCalls += 1;
      final session = _FakeSession();
      sessions.add(session);
      return session;
    }

    final first = await controller.acquire(
      scope: 'did:elix:alice',
      authenticate: authenticate,
    );
    await first!.release();
    now = now.add(const Duration(seconds: 50));
    final reused = await controller.acquire(
      scope: 'did:elix:alice',
      authenticate: authenticate,
    );
    await reused!.release();

    now = now.add(const Duration(seconds: 11));
    final renewed = await controller.acquire(
      scope: 'did:elix:alice',
      authenticate: authenticate,
    );
    await renewed!.release();

    expect(authenticationCalls, 2);
    expect(sessions.first.closeCalls, 1);
    await controller.invalidate();
    expect(sessions.last.closeCalls, 1);
  });

  test('identity changes cannot reuse another DID authorization', () async {
    var authenticationCalls = 0;
    final sessions = <_FakeSession>[];
    final controller = SyncAuthorizationController();

    Future<SyncAuthenticationSession?> authenticate() async {
      authenticationCalls += 1;
      final session = _FakeSession();
      sessions.add(session);
      return session;
    }

    final alice = await controller.acquire(
      scope: 'did:elix:alice',
      authenticate: authenticate,
    );
    await alice!.release();
    final bob = await controller.acquire(
      scope: 'did:elix:bob',
      authenticate: authenticate,
    );
    await bob!.release();

    expect(authenticationCalls, 2);
    expect(sessions.first.closeCalls, 1);
    await controller.invalidate();
  });

  test(
    'lifecycle invalidation closes an active authorization fail closed',
    () async {
      var authenticationCalls = 0;
      final sessions = <_FakeSession>[];
      final controller = SyncAuthorizationController();

      Future<SyncAuthenticationSession?> authenticate() async {
        authenticationCalls += 1;
        final session = _FakeSession();
        sessions.add(session);
        return session;
      }

      final active = await controller.acquire(
        scope: 'did:elix:alice',
        authenticate: authenticate,
      );
      await controller.invalidate();
      expect(sessions.single.closeCalls, 1);
      await active!.release();
      expect(sessions.single.closeCalls, 1);

      final resumed = await controller.acquire(
        scope: 'did:elix:alice',
        authenticate: authenticate,
      );
      await resumed!.release();
      expect(authenticationCalls, 2);
      await controller.invalidate();
    },
  );
}

class _FakeSession implements SyncAuthenticationSession {
  int closeCalls = 0;

  @override
  bool get reuseHardwareAuthenticationContext => true;

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}
