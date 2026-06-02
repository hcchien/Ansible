# App-Mediated Web Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Current alignment note, 2026-06-02: this May 11 plan originally implemented a
> bearer-token-shaped web-session path. The current browser path was hardened by
> the Relay / Forum Host boundary work: the relay sets an httpOnly
> `trisaura_session` cookie on approved challenge polling, browser APIs use
> same-origin credentials, public reads omit credentials, and the frontend no
> longer stores or sends bearer session tokens. `VerifyWebSession` accepts the
> cookie and still supports bearer tokens as a compatibility path for
> non-browser/API callers.

**Goal:** Add an app-mediated login and authorization path that lets the distribution web UI act as a scoped self-custody DID session without exporting the app user's DID private key to the browser.

**Architecture:** The relay issues web-session challenges and stores pending approvals. The app receives a QR/deep-link payload, displays the requested origin/scopes/expiry, signs a canonical session grant with `DidSigner`, and submits it to the relay. The relay verifies the signature against the active DID cache, issues a short-lived session, installs it in the browser through an httpOnly cookie, and enforces session scopes on web-facing Forum Host APIs.

**Tech Stack:** Dart, Flutter, `ansible_did`, `flutter_secure_storage`, `app_links`, `mobile_scanner`, Elixir/Phoenix Plug router, Jason, Ecto-ready GenServer state, `flutter test`, `dart test`, `mix test`.

---

## Source Documents

Read these first:

- `docs/superpowers/specs/2026-05-11-app-mediated-web-session-design.md`
- `docs/superpowers/specs/2026-05-09-federation-strategy-design.md`
- `docs/superpowers/specs/2026-05-10-forum-host-board-design.md`
- `docs/security/sosp.md`
- `docs/protocol/tris_aura_sync_spec_v2.0.md`

## File Structure

Create relay web-session modules:

- `ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex`
- `ansible_relay/phoenix/lib/ansible_relay/web/plugs/verify_web_session.ex`
- `ansible_relay/phoenix/lib/ansible_relay/web/controllers/web_session_controller.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/application.ex`
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`
- Test `ansible_relay/phoenix/test/web_session_controller_test.exs`
- Test `ansible_relay/phoenix/test/verify_web_session_test.exs`

Create app web-session modules:

- `ansible_node/app/lib/services/web_session_grant_service.dart`
- `ansible_node/app/lib/services/web_session_approval_client.dart`
- `ansible_node/app/lib/screens/web_session_approval_screen.dart`
- `ansible_node/app/lib/screens/web_session_scanner_screen.dart`
- Modify `ansible_node/app/pubspec.yaml`
- Modify `ansible_node/app/lib/main.dart`
- Test `ansible_node/app/test/web_session_grant_service_test.dart`
- Test `ansible_node/app/test/web_session_approval_client_test.dart`
- Test `ansible_node/app/test/web_session_approval_screen_test.dart`

## Task 1: Relay Web Session Challenge Store

**Files:**

- Create `ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex`.
- Modify `ansible_relay/phoenix/lib/ansible_relay/application.ex`.
- Test `ansible_relay/phoenix/test/web_session_controller_test.exs`.

- [x] **Step 1: Write failing store tests**

Add tests that prove challenge creation, lookup, approval, token lookup, expiry,
and one-time challenge consumption:

```elixir
test "approved challenge creates a scoped session token" do
  {:ok, challenge} =
    WebSessionStore.issue_challenge(%{
      "web_origin" => "https://trisaura.io",
      "relay_origin" => "https://relay.trisaura.io",
      "scopes" => ["forum:read", "forum:post"],
      "ttl_seconds" => 300
    })

  assert {:ok, pending} = WebSessionStore.get_challenge(challenge.challenge_id)
  assert pending.status == "pending"

  assert {:ok, session} =
           WebSessionStore.approve_challenge(challenge.challenge_id, %{
             subject_did: "did:plc:abc23456789",
             approving_device_id: "app_device_abc",
             scopes: ["forum:read", "forum:post"],
             expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
           })

  assert {:ok, found} = WebSessionStore.get_session(session.session_token)
  assert found.subject_did == "did:plc:abc23456789"
  assert found.scopes == ["forum:read", "forum:post"]
  assert {:error, :consumed} = WebSessionStore.get_challenge(challenge.challenge_id)
end
```

Run:

```bash
cd ansible_relay/phoenix
mix test test/web_session_controller_test.exs
```

Expected: fail because `WebSessionStore` does not exist.

- [x] **Step 2: Implement `WebSessionStore`**

Implement a GenServer with these public functions:

```elixir
def issue_challenge(attrs)
def get_challenge(challenge_id)
def approve_challenge(challenge_id, attrs)
def reject_challenge(challenge_id)
def poll_challenge(challenge_id)
def get_session(session_token)
def revoke_session(session_token)
```

Use random URL-safe ids:

```elixir
defp token(prefix) do
  "#{prefix}_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
end
```

Store challenge fields: `challenge_id`, `web_origin`, `relay_origin`, `scopes`,
`status`, `expires_at`, and `approved_session_token`.

Store session fields: `session_token`, `subject_did`, `web_origin`,
`relay_origin`, `scopes`, `trust_tier`, `expires_at`, `created_at`, and
`revoked_at`.

- [x] **Step 3: Register store in supervision tree**

In `ansible_relay/phoenix/lib/ansible_relay/application.ex`, add:

```elixir
{AnsibleRelay.WebSessionStore, []}
```

after existing cache/store processes so the controller can use it.

- [x] **Step 4: Verify store tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/web_session_controller_test.exs
```

Expected: challenge/session store tests pass.

## Task 2: Relay Web Session HTTP API

**Files:**

- Create `ansible_relay/phoenix/lib/ansible_relay/web/controllers/web_session_controller.ex`.
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`.
- Test `ansible_relay/phoenix/test/web_session_controller_test.exs`.

- [x] **Step 1: Write failing controller tests**

Add tests for these endpoints:

```text
POST /api/v1/web-sessions/challenges
GET  /api/v1/web-sessions/challenges/:id
POST /api/v1/web-sessions/approve
POST /api/v1/web-sessions/reject
POST /api/v1/web-sessions/revoke
GET  /api/v1/web-sessions/me
```

The challenge response must include:

```json
{
  "challenge_id": "wsc_...",
  "expires_at": "2026-05-11T13:00:00Z",
  "deep_link": "trisaura://web-session/approve?challenge_id=wsc_...",
  "qr_payload": "trisaura://web-session/approve?challenge_id=wsc_..."
}
```

Run:

```bash
cd ansible_relay/phoenix
mix test test/web_session_controller_test.exs
```

Expected: fail because routes and controller do not exist.

- [x] **Step 2: Implement challenge and polling routes**

Add routes to `router.ex`:

```elixir
post "/api/v1/web-sessions/challenges" do
  AnsibleRelay.Web.Controllers.WebSessionController.create_challenge(conn, conn.body_params)
end

get "/api/v1/web-sessions/challenges/:id" do
  AnsibleRelay.Web.Controllers.WebSessionController.poll_challenge(conn, %{"challenge_id" => id})
end
```

Validate `web_origin`, `relay_origin`, `scopes`, and pending challenge TTL. Allow
only these scopes in the first implementation: `forum:read`, `forum:post`,
`forum:reply`, and `identity:display`.

- [x] **Step 3: Implement approval verification**

Add approval route:

```elixir
post "/api/v1/web-sessions/approve" do
  AnsibleRelay.Web.Controllers.WebSessionController.approve(conn, conn.body_params)
end
```

The approval body must contain:

```json
{
  "challenge_id": "wsc_...",
  "subject_did": "did:plc:...",
  "grant": {},
  "signature": "hex-ed25519"
}
```

The `grant` object includes `approving_device_id`.

Controller verification order:

1. Load pending challenge.
2. Validate `grant.challenge_id`, `grant.web_origin`, `grant.relay_origin`,
   scopes, and expiry against the pending challenge.
3. Validate `grant.approving_device_id` so approvals can be rate-limited per
   app device.
4. Get public key from `IdentityCache.public_key_hex(subject_did)`.
5. Verify Ed25519 signature over canonical grant JSON with `SigVerifier`.
6. Enforce active-session and approval-rate policy.
7. Approve challenge and return `session_token`, `expires_at`, `trust_tier`.

- [x] **Step 4: Implement reject, revoke, and me routes**

Add routes:

```elixir
post "/api/v1/web-sessions/reject" do
  AnsibleRelay.Web.Controllers.WebSessionController.reject(conn, conn.body_params)
end

post "/api/v1/web-sessions/revoke" do
  AnsibleRelay.Web.Controllers.WebSessionController.revoke(conn, conn.body_params)
end

get "/api/v1/web-sessions/me" do
  AnsibleRelay.Web.Controllers.WebSessionController.me(conn, conn.req_headers)
end
```

Current implementation note: `me` accepts the browser httpOnly
`trisaura_session` cookie and may also accept `Authorization: Bearer
<session_token>` for compatibility. It returns:

```json
{
  "subject_did": "did:plc:...",
  "trust_tier": "self_custody_did",
  "scopes": ["forum:read", "forum:post"],
  "expires_at": "2026-05-11T13:00:00Z"
}
```

- [x] **Step 5: Verify API tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/web_session_controller_test.exs
```

Expected: all web session controller tests pass.

## Task 3: Web Session Authorization Plug

**Files:**

- Create `ansible_relay/phoenix/lib/ansible_relay/web/plugs/verify_web_session.ex`.
- Test `ansible_relay/phoenix/test/verify_web_session_test.exs`.

- [x] **Step 1: Write failing plug tests**

Test these cases:

- missing bearer token returns `401`.
- unknown token returns `401`.
- expired or revoked token returns `401`.
- token missing required scope returns `403`.
- valid token assigns `:web_session` and `:verified_did`.

Run:

```bash
cd ansible_relay/phoenix
mix test test/verify_web_session_test.exs
```

Expected: fail because the plug does not exist.

- [x] **Step 2: Implement `VerifyWebSession`**

Expose:

```elixir
def call(conn, required_scopes)
```

Behavior:

- Parse the `trisaura_session` cookie or compatible `Authorization` bearer
  header.
- Load session from `WebSessionStore.get_session/1`.
- Reject expired or revoked session.
- Require all `required_scopes`.
- Assign `:web_session` and `:verified_did`.

- [x] **Step 3: Verify plug tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/verify_web_session_test.exs
```

Expected: all plug tests pass.

## Task 4: App Grant Model And Signing Service

**Files:**

- Create `ansible_node/app/lib/services/web_session_grant_service.dart`.
- Test `ansible_node/app/test/web_session_grant_service_test.dart`.

- [x] **Step 1: Write failing grant canonicalization tests**

Add a deterministic test:

```dart
test('builds canonical web session grant payload', () {
  final grant = WebSessionGrant(
    challengeId: 'wsc_test',
    relayOrigin: 'https://relay.trisaura.io',
    webOrigin: 'https://trisaura.io',
    subjectDid: 'did:plc:abc23456789',
    approvingDeviceId: 'app_device_abc',
    scopes: const ['forum:post', 'forum:read'],
    expiresAt: DateTime.utc(2026, 5, 11, 13),
    createdAt: DateTime.utc(2026, 5, 11, 12, 45),
  );

  expect(
    grant.canonicalJson(),
    '{"approving_device_id":"app_device_abc","challenge_id":"wsc_test","created_at":"2026-05-11T12:45:00.000Z","expires_at":"2026-05-11T13:00:00.000Z","relay_origin":"https://relay.trisaura.io","scopes":["forum:post","forum:read"],"subject_did":"did:plc:abc23456789","type":"io.trisaura.webSessionGrant","version":1,"web_origin":"https://trisaura.io"}',
  );
});
```

Run:

```bash
cd ansible_node/app
flutter test test/web_session_grant_service_test.dart
```

Expected: fail because the service does not exist.

- [x] **Step 2: Implement grant model**

Add:

```dart
class WebSessionGrant {
  final String challengeId;
  final String relayOrigin;
  final String webOrigin;
  final String subjectDid;
  final List<String> scopes;
  final DateTime expiresAt;
  final DateTime createdAt;

  Map<String, Object?> toJson();
  String canonicalJson();
}
```

Use a fixed key order in `canonicalJson()` so relay verification signs the same
bytes in every runtime.

- [x] **Step 3: Implement signing service**

Add:

```dart
class WebSessionGrantService {
  final DidSigner signer;

  WebSessionGrantService({DidSigner? signer})
      : signer = signer ?? DidSignerImpl();

  Future<SignedWebSessionGrant> sign(WebSessionGrant grant) async {
    final signature = await signer.sign(utf8.encode(grant.canonicalJson()));
    return SignedWebSessionGrant(grant: grant, signatureHex: signature.hex);
  }
}
```

- [x] **Step 4: Verify grant tests**

Run:

```bash
cd ansible_node/app
flutter test test/web_session_grant_service_test.dart
```

Expected: all grant tests pass.

## Task 5: App Relay Approval Client

**Files:**

- Create `ansible_node/app/lib/services/web_session_approval_client.dart`.
- Test `ansible_node/app/test/web_session_approval_client_test.dart`.

- [x] **Step 1: Write failing client tests**

Use `http/testing.dart` to verify:

- `fetchChallenge` calls `GET /api/v1/web-sessions/challenges/:id`.
- `approve` posts `challenge_id`, `subject_did`, `grant`, and `signature`.
- `reject` posts `challenge_id`.
- relay errors are exposed as typed exceptions.

Run:

```bash
cd ansible_node/app
flutter test test/web_session_approval_client_test.dart
```

Expected: fail because the client does not exist.

- [x] **Step 2: Implement approval client**

Add methods:

```dart
Future<WebSessionChallenge> fetchChallenge(String challengeId);
Future<WebSessionApprovalResult> approve(SignedWebSessionGrant grant);
Future<void> reject(String challengeId);
```

Use the same base URL pattern as existing relay clients.

- [x] **Step 3: Verify client tests**

Run:

```bash
cd ansible_node/app
flutter test test/web_session_approval_client_test.dart
```

Expected: all approval client tests pass.

## Task 6: App Deep Link, QR Scanner, And Approval UI

**Files:**

- Modify `ansible_node/app/pubspec.yaml`.
- Create `ansible_node/app/lib/screens/web_session_approval_screen.dart`.
- Create `ansible_node/app/lib/screens/web_session_scanner_screen.dart`.
- Modify `ansible_node/app/lib/main.dart`.
- Test `ansible_node/app/test/web_session_approval_screen_test.dart`.

- [x] **Step 1: Add app dependencies**

Add dependencies:

```yaml
app_links: ^6.4.0
mobile_scanner: ^7.0.0
```

Run:

```bash
cd ansible_node/app
flutter pub get
```

Expected: lockfile updates and dependency resolution succeeds.

- [x] **Step 2: Write failing approval screen tests**

Test that the approval screen:

- shows `webOrigin`, `relayOrigin`, scopes, expiry, and DID.
- disables approve for expired challenges.
- calls `approve` only after user taps the approve button.
- calls `reject` when user taps reject.

Run:

```bash
cd ansible_node/app
flutter test test/web_session_approval_screen_test.dart
```

Expected: fail because screens do not exist.

- [x] **Step 3: Implement deep link parser**

Support payloads shaped as:

```text
trisaura://web-session/approve?challenge_id=wsc_abc&relay_origin=https%3A%2F%2Frelay.trisaura.io
```

Reject payloads without `challenge_id` or with non-http relay origins.

- [x] **Step 4: Implement approval screen**

The screen loads challenge metadata through `WebSessionApprovalClient`, builds a
`WebSessionGrant`, signs through `WebSessionGrantService`, and submits approval.
The UI must show web origin, relay origin, requested scopes, expiry, and current
DID.

- [x] **Step 5: Implement QR scanner screen**

Use `mobile_scanner` to scan the same deep-link payload. On first valid scan,
stop scanning and navigate to `WebSessionApprovalScreen`.

- [x] **Step 6: Wire deep links in app startup**

In `main.dart`, subscribe to `AppLinks().uriLinkStream` and route valid
web-session approval links to the approval screen. Keep invalid links ignored
with a visible error snackbar when the app is in foreground.

- [x] **Step 7: Verify app UI tests**

Run:

```bash
cd ansible_node/app
flutter test test/web_session_approval_screen_test.dart
```

Expected: all approval UI tests pass.

## Task 7: Scope Enforcement Smoke Path

**Files:**

- Modify `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`.
- Modify `ansible_relay/phoenix/lib/ansible_relay/web/router.ex`.
- Test `ansible_relay/phoenix/test/forum_host_controller_test.exs`.

- [x] **Step 1: Write failing scoped write tests**

Add tests that prove a future web write endpoint requires `forum:post`:

```elixir
test "web session must include forum:post to create a hosted web thread" do
  token = approved_session_token(scopes: ["forum:read"])

  response =
    conn(:post, "/api/v1/forum-host/web/threads", %{"title" => "Hello"})
    |> put_req_header("authorization", "Bearer #{token}")
    |> Router.call([])

  assert response.status == 403
end
```

Run:

```bash
cd ansible_relay/phoenix
mix test test/forum_host_controller_test.exs
```

Expected: fail because scoped endpoint does not exist.

- [x] **Step 2: Add minimal scoped endpoint**

Add `POST /api/v1/forum-host/web/threads` as a smoke endpoint that:

- Requires a valid web session.
- Requires `forum:post`.
- Returns `202` with `accepted: true`, `subject_did`, and `trust_tier`.
- Does not replace the full Forum Host thread implementation plan.

- [x] **Step 3: Verify scoped write tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/forum_host_controller_test.exs test/verify_web_session_test.exs
```

Expected: all scoped write tests pass.

## Task 8: Full Verification

**Files:**

- All files changed by Tasks 1-7.

- [x] **Step 1: Run relay web session tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/web_session_controller_test.exs test/verify_web_session_test.exs test/forum_host_controller_test.exs
```

Expected: all selected relay tests pass.

- [x] **Step 2: Run app web session tests**

Run:

```bash
cd ansible_node/app
flutter test test/web_session_grant_service_test.dart test/web_session_approval_client_test.dart test/web_session_approval_screen_test.dart
```

Expected: all selected app tests pass.

- [x] **Step 3: Run broader affected suites**

Run:

```bash
cd ansible_relay/phoenix
mix test
cd ../../ansible_node/app
flutter test
```

Expected: full relay and Flutter suites pass.

Status: full relay `mix test` passes. Full Flutter `flutter test` passes after
the app-mediated session policy and revocation updates.

## Acceptance Checklist

- [x] Relay can create, poll, approve, reject, revoke, and inspect web sessions.
- [x] Relay verifies session grants with active DID public keys.
- [x] Relay rejects replayed, expired, malformed, or over-scoped grants.
- [x] Relay caps app-approved web sessions at 5 active sessions per DID.
- [x] Relay limits each app device to 3 approvals per DID per rolling hour.
- [x] Forum Host web writes consume DID-level rate-limit tokens.
- [x] App can parse deep-link and QR web-session approval payloads.
- [x] App approval UI shows origin, scopes, expiry, and DID before signing.
- [x] Browser receives only relay-issued session state, currently through an
  httpOnly cookie; it never receives DID private keys.
- [x] A scoped Forum Host smoke endpoint enforces `forum:post`.
- [x] Tests cover relay controller, relay auth plug, app grant service, approval client, and approval UI.
