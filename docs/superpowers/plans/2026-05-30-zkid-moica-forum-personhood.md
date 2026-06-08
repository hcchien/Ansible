# zkID MOICA Forum Personhood Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Status:** Paused for the MobileMoica RP path. Use this plan only if a true
> zkID/Mopro TW FidO binding is available and APP2APP raw artifacts remain
> inside the local proving boundary. The direct MobileMoica relying-party path
> is specified separately in
> `docs/superpowers/specs/2026-05-30-mobilemoica-rp-explicit-disclosure-design.md`.

**Goal:** Add an optional zkID/OpenAC MOICA natural-person-certificate path that lets a Wallet obtain a `TrisAuraHumanityCredential` for forum trust-tier use without disclosing raw legal identity to Forum Hosts, Relays, or ordinary verifiers.

**Architecture:** The Wallet performs MOICA proof generation locally and submits only zkID linked proofs plus public verification inputs to the Issuer. The Issuer delegates cryptographic verification to a configured zkID verifier, stores only a server-keyed commitment derived from the app-scoped nullifier, and issues a normal `TrisAuraHumanityCredential`; the Relay and Forum Host continue to consume only the resulting verified-human trust tier. This first version is off-chain only and intentionally enforces one verification per MOICA certificate/key/app nullifier, not a global one-human invariant.

**Tech Stack:** Go 1.22 issuer HTTP API, zkID/OpenAC verifier HTTP contract, Dart/Flutter Wallet UI and client services, iOS/Android TW FidO zkID native prover bridge, Elixir/Phoenix Relay reputation and web-session trust-tier propagation, Node frontend smoke tests.

---

## Source Documents

Read these before implementation:

- `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
- `docs/superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md`
- `docs/architecture/tw_provider_production_integration.md`
- `docs/deployment/tw_provider_issuer_deployment.md`
- `docs/superpowers/specs/2026-05-10-forum-host-board-design.md`
- zkID spec: `https://github.com/privacy-ethereum/zkID/blob/main/specs/2-zk-proof-of-personhood/README.md`
- User-provided MobileMoica / TW FidO APP2APP integration test notes. Treat
  service credentials, checksums, tickets, signed responses, and sample
  certificate material from that attachment as sensitive local input; do not
  commit them, print them in logs, or convert them into test fixtures.

## Constitution Review

This plan touches identity, credentials, verification, Relay trust, and Forum Host behavior, so the constitution applies.

- User-controlled credential: a MOICA natural person certificate accessed through local Wallet proving. The Wallet never sends the full certificate, PIN, raw serial number, legal name, national ID, certificate public key, or private key to Tris-Aura services.
- Data leaving the device: only the zkID linked proof envelope and public inputs required by zkID (`pk_commit`, issuer modulus limbs, `smt_root`, app-bound `challenge`, app-bound `app_id_packed`, and `nullifier`). The UI must show this before submission.
- Minimum claim: "holder can produce a valid zkID MOICA proof for this app and challenge." The issued VC exposes only `humanVerified`, `assuranceLevel`, `assuranceMethod`, and `jurisdiction`.
- Duplicate prevention: the Issuer stores `commitment.Compute(pepper, nullifier, "zkid_moica_openac_v1:"+appID)` and never stores or issues the raw nullifier after verification.
- Forum behavior: Forum Host and distribution frontend see only Relay web-session `trust_tier: "verified_human"` or a normal verified-human VP result. They never see the zkID nullifier or MOICA certificate fields.
- First-version limitation: zkID v0.1 allows one verification per certificate/key/app nullifier. Renewal, physical card versus TW FidO, or changed key material may create a different nullifier. Do not market this as strict one-human-one-account.
- Existing gaps remain: hardware-backed DID key storage and external host
  compliance persistence/policy integration are still known gaps and are not
  solved by this plan.

## MobileMoica APP2APP Document Review

The provided MobileMoica / TW FidO APP2APP notes confirm that a true-device
deep link flow exists, using a `mobilemoica://.../a2a/verifySign` URL and a
return URL back into Elix. They do not, by themselves, provide a zkID proof
generation contract.

The APP2APP contract described in those notes is a relying-party signing flow:
the service provider requests a short-lived ticket, opens the TW FidO app, then
polls for a PKCS#7 signed response. The ticket request includes a raw national
ID input, and the signed response includes certificate subject data that the
notes themselves mark as personal information.

That direct APP2APP flow conflicts with this zkID forum-personhood plan if it
is implemented by either:

- sending a raw national ID to a first-party Issuer only to raise forum trust,
- embedding the service AES key or checksum logic in the Wallet app,
- sending `signed_response`, legal name, certificate serial, certificate
  subject, or raw certificate material to Tris-Aura services, or
- issuing a VC from MobileMoica PKCS#7 validation without a zkID proof/nullifier
  boundary.

Therefore Task 7's true-device acceptance criterion is gated as follows: it is
acceptable only if the native `TwFidoZkIDMOICAProver` uses a zkID/Mopro TW FidO
binding that keeps APP2APP artifacts local to the user-controlled proving
boundary and returns only the zkID linked proof envelope to Dart. If the only
available integration is the direct MobileMoica APP2APP relying-party flow, this
plan must stop before implementation code and be replaced by a separate
explicit-disclosure MobileMoica RP spec with legal/privacy review. That separate
spec would not be a zkID implementation.

## File Structure

Issuer:

- Create: `ansible_issuer/go/internal/provider/zkid_openac.go`
- Create: `ansible_issuer/go/internal/provider/zkid_openac_test.go`
- Create: `ansible_issuer/go/internal/provider/zkid_verifier_client.go`
- Create: `ansible_issuer/go/internal/provider/zkid_verifier_client_test.go`
- Create: `ansible_issuer/go/internal/api/zkid_moica.go`
- Create: `ansible_issuer/go/internal/api/zkid_moica_test.go`
- Modify: `ansible_issuer/go/internal/api/handler.go`
- Modify: `ansible_issuer/go/internal/vc/issuer.go`
- Modify: `ansible_issuer/go/internal/vc/issuer_test.go`
- Modify: `ansible_issuer/go/cmd/server/main.go`
- Modify: `docs/deployment/tw_provider_issuer_deployment.md`

Wallet and app:

- Modify: `ansible_node/app/lib/services/vc_issuer_client.dart`
- Create: `ansible_node/app/lib/services/zkid_moica_prover.dart`
- Create: `ansible_node/app/lib/screens/zkid_moica_credential_screen.dart`
- Modify: `ansible_node/app/lib/screens/credential_issuance_wizard.dart`
- Modify: `ansible_node/app/ios/Runner/AppDelegate.swift`
- Modify: `ansible_node/app/ios/Runner/Info.plist`
- Modify: `ansible_node/app/android/app/src/main/kotlin/io/trisaura/ansible_node/MainActivity.kt`
- Modify: `ansible_node/app/android/app/src/main/AndroidManifest.xml`
- Modify: `ansible_node/app/test/vc_issuer_client_test.dart`
- Create: `ansible_node/app/test/zkid_moica_credential_screen_test.dart`

Relay and Forum Host:

- Modify: `ansible_relay/phoenix/lib/ansible_relay/vp_verifier.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/reputation_controller.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/web_session_controller.ex`
- Modify: `ansible_relay/phoenix/test/vp_verifier_test.exs`
- Modify: `ansible_relay/phoenix/test/reputation_controller_test.exs`
- Modify: `ansible_relay/phoenix/test/web_session_controller_test.exs`
- Modify: `ansible_distribution_frontend/test/forum_login_app.test.mjs`

Docs:

- Create: `docs/architecture/zkid_moica_forum_personhood.md`

## Task 1: Issuer zkID Proof Contract Types

**Files:**

- Create: `ansible_issuer/go/internal/provider/zkid_openac.go`
- Create: `ansible_issuer/go/internal/provider/zkid_openac_test.go`

- [ ] **Step 1: Write failing proof contract tests**

Create `ansible_issuer/go/internal/provider/zkid_openac_test.go`:

```go
package provider_test

import (
	"testing"

	"github.com/trisaura/ansible_issuer/internal/provider"
)

func validSubmission() provider.ZkIDLinkedProofSubmission {
	return provider.ZkIDLinkedProofSubmission{
		CertChain: provider.ZkIDProofEnvelope{
			Proof: "cert-proof-bytes",
			PublicInputs: map[string]any{
				"pk_commit": "12345",
				"modulus":   []any{"11", "22"},
				"smt_root":  "0xrevocationroot",
			},
		},
		DeviceSig: provider.ZkIDProofEnvelope{
			Proof: "device-proof-bytes",
			PublicInputs: map[string]any{
				"pk_commit":     "12345",
				"nullifier":     "0xappscopednullifier",
				"app_id_packed": "4242",
				"challenge":     "0xchallenge",
			},
		},
	}
}

func TestZkIDLinkedProofSubmissionExtractsPublicValues(t *testing.T) {
	values, err := provider.ExtractZkIDPublicValues(validSubmission())
	if err != nil {
		t.Fatalf("extract values: %v", err)
	}
	if values.Nullifier != "0xappscopednullifier" {
		t.Fatalf("unexpected nullifier: %+v", values)
	}
	if values.PKCommit != "12345" || values.AppIDPacked != "4242" || values.Challenge != "0xchallenge" {
		t.Fatalf("unexpected public values: %+v", values)
	}
}

func TestZkIDLinkedProofSubmissionRejectsMismatchedPKCommit(t *testing.T) {
	submission := validSubmission()
	submission.DeviceSig.PublicInputs["pk_commit"] = "different"
	_, err := provider.ExtractZkIDPublicValues(submission)
	if err != provider.ErrZkIDLinkedProofMismatch {
		t.Fatalf("expected mismatch, got %v", err)
	}
}

func TestZkIDLinkedProofSubmissionRejectsMissingNullifier(t *testing.T) {
	submission := validSubmission()
	delete(submission.DeviceSig.PublicInputs, "nullifier")
	_, err := provider.ExtractZkIDPublicValues(submission)
	if err != provider.ErrZkIDMissingPublicInput {
		t.Fatalf("expected missing public input, got %v", err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./internal/provider
```

Expected: FAIL because `ZkIDLinkedProofSubmission`, `ZkIDProofEnvelope`, `ExtractZkIDPublicValues`, `ErrZkIDLinkedProofMismatch`, and `ErrZkIDMissingPublicInput` do not exist.

- [ ] **Step 3: Implement zkID contract types**

Create `ansible_issuer/go/internal/provider/zkid_openac.go`:

```go
package provider

import "errors"

var (
	ErrZkIDMissingPublicInput  = errors.New("zkid missing public input")
	ErrZkIDLinkedProofMismatch = errors.New("zkid linked proof mismatch")
)

type ZkIDProofEnvelope struct {
	Proof        string         `json:"proof"`
	PublicInputs map[string]any `json:"public_inputs"`
}

type ZkIDLinkedProofSubmission struct {
	CertChain ZkIDProofEnvelope `json:"cert_chain"`
	DeviceSig ZkIDProofEnvelope `json:"device_sig"`
}

type ZkIDPublicValues struct {
	PKCommit    string
	SMTRoot     string
	Nullifier   string
	AppIDPacked string
	Challenge   string
}

func ExtractZkIDPublicValues(submission ZkIDLinkedProofSubmission) (ZkIDPublicValues, error) {
	certPKCommit, ok := stringInput(submission.CertChain.PublicInputs, "pk_commit")
	if !ok {
		return ZkIDPublicValues{}, ErrZkIDMissingPublicInput
	}
	devicePKCommit, ok := stringInput(submission.DeviceSig.PublicInputs, "pk_commit")
	if !ok {
		return ZkIDPublicValues{}, ErrZkIDMissingPublicInput
	}
	if certPKCommit != devicePKCommit {
		return ZkIDPublicValues{}, ErrZkIDLinkedProofMismatch
	}
	smtRoot, ok := stringInput(submission.CertChain.PublicInputs, "smt_root")
	if !ok {
		return ZkIDPublicValues{}, ErrZkIDMissingPublicInput
	}
	nullifier, ok := stringInput(submission.DeviceSig.PublicInputs, "nullifier")
	if !ok {
		return ZkIDPublicValues{}, ErrZkIDMissingPublicInput
	}
	appID, ok := stringInput(submission.DeviceSig.PublicInputs, "app_id_packed")
	if !ok {
		return ZkIDPublicValues{}, ErrZkIDMissingPublicInput
	}
	challenge, ok := stringInput(submission.DeviceSig.PublicInputs, "challenge")
	if !ok {
		return ZkIDPublicValues{}, ErrZkIDMissingPublicInput
	}
	return ZkIDPublicValues{
		PKCommit:    certPKCommit,
		SMTRoot:     smtRoot,
		Nullifier:   nullifier,
		AppIDPacked: appID,
		Challenge:   challenge,
	}, nil
}

func stringInput(inputs map[string]any, key string) (string, bool) {
	value, ok := inputs[key]
	if !ok {
		return "", false
	}
	switch typed := value.(type) {
	case string:
		return typed, typed != ""
	default:
		return "", false
	}
}
```

- [ ] **Step 4: Verify provider tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./internal/provider
```

Expected: PASS.

## Task 2: Issuer zkID Verifier Client

**Files:**

- Create: `ansible_issuer/go/internal/provider/zkid_verifier_client.go`
- Create: `ansible_issuer/go/internal/provider/zkid_verifier_client_test.go`

- [ ] **Step 1: Write failing HTTP verifier client tests**

Create `ansible_issuer/go/internal/provider/zkid_verifier_client_test.go`:

```go
package provider_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/trisaura/ansible_issuer/internal/provider"
)

func TestHTTPZkIDVerifierClientFetchesChallengeAndStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/challenge":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"challenge":  "0xchallenge",
				"app_id":     "4242",
				"expires_at": "2026-05-30T12:05:00Z",
			})
		case "/smt-root/status":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"smt_root": "0xrevocationroot",
			})
		case "/issuer-cert/status":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"accepted_modulus": []string{"11", "22"},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := provider.NewHTTPZkIDVerifierClient(server.URL, server.Client())
	challenge, err := client.Challenge(context.Background())
	if err != nil {
		t.Fatalf("challenge: %v", err)
	}
	status, err := client.Status(context.Background())
	if err != nil {
		t.Fatalf("status: %v", err)
	}
	if challenge.Challenge != "0xchallenge" || status.SMTRoot != "0xrevocationroot" {
		t.Fatalf("unexpected verifier data: %+v %+v", challenge, status)
	}
}

func TestHTTPZkIDVerifierClientSubmitsLinkedProof(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/link-verify" {
			http.NotFound(w, r)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"decision":    "pass",
			"verified_at": "2026-05-30T12:01:00Z",
		})
	}))
	defer server.Close()

	client := provider.NewHTTPZkIDVerifierClient(server.URL, server.Client())
	decision, err := client.VerifyLinkedProof(context.Background(), validSubmission())
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if decision.Decision != "pass" {
		t.Fatalf("unexpected decision: %+v", decision)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./internal/provider
```

Expected: FAIL because the HTTP verifier client does not exist.

- [ ] **Step 3: Implement verifier client interface and HTTP adapter**

Create `ansible_issuer/go/internal/provider/zkid_verifier_client.go`:

```go
package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

type ZkIDVerifierClient interface {
	Challenge(context.Context) (ZkIDChallenge, error)
	Status(context.Context) (ZkIDVerifierStatus, error)
	VerifyLinkedProof(context.Context, ZkIDLinkedProofSubmission) (ZkIDVerifyDecision, error)
}

type ZkIDChallenge struct {
	Challenge string `json:"challenge"`
	AppID     string `json:"app_id"`
	ExpiresAt string `json:"expires_at"`
}

type ZkIDVerifierStatus struct {
	SMTRoot         string   `json:"smt_root"`
	AcceptedModulus []string `json:"accepted_modulus"`
}

type ZkIDVerifyDecision struct {
	Decision   string `json:"decision"`
	ErrorCode  string `json:"error_code,omitempty"`
	VerifiedAt string `json:"verified_at,omitempty"`
}

type HTTPZkIDVerifierClient struct {
	baseURL string
	client  *http.Client
}

func NewHTTPZkIDVerifierClient(baseURL string, client *http.Client) *HTTPZkIDVerifierClient {
	if client == nil {
		client = http.DefaultClient
	}
	return &HTTPZkIDVerifierClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		client:  client,
	}
}

func (c *HTTPZkIDVerifierClient) Challenge(ctx context.Context) (ZkIDChallenge, error) {
	var out ZkIDChallenge
	err := c.postJSON(ctx, "/challenge", map[string]any{}, &out)
	return out, err
}

func (c *HTTPZkIDVerifierClient) Status(ctx context.Context) (ZkIDVerifierStatus, error) {
	var smt struct {
		SMTRoot string `json:"smt_root"`
	}
	if err := c.getJSON(ctx, "/smt-root/status", &smt); err != nil {
		return ZkIDVerifierStatus{}, err
	}
	var issuer struct {
		AcceptedModulus []string `json:"accepted_modulus"`
	}
	if err := c.getJSON(ctx, "/issuer-cert/status", &issuer); err != nil {
		return ZkIDVerifierStatus{}, err
	}
	return ZkIDVerifierStatus{SMTRoot: smt.SMTRoot, AcceptedModulus: issuer.AcceptedModulus}, nil
}

func (c *HTTPZkIDVerifierClient) VerifyLinkedProof(ctx context.Context, submission ZkIDLinkedProofSubmission) (ZkIDVerifyDecision, error) {
	var out ZkIDVerifyDecision
	err := c.postJSON(ctx, "/link-verify", submission, &out)
	return out, err
}

func (c *HTTPZkIDVerifierClient) getJSON(ctx context.Context, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+path, nil)
	if err != nil {
		return err
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("zkid verifier %s returned %d", path, resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (c *HTTPZkIDVerifierClient) postJSON(ctx context.Context, path string, body any, out any) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+path, bytes.NewReader(encoded))
	if err != nil {
		return err
	}
	req.Header.Set("content-type", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("zkid verifier %s returned %d", path, resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}
```

- [ ] **Step 4: Verify provider tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./internal/provider
```

Expected: PASS.

## Task 3: Issuer VC Issuance Method For zkID MOICA

**Files:**

- Modify: `ansible_issuer/go/internal/vc/issuer.go`
- Modify: `ansible_issuer/go/internal/vc/issuer_test.go`

- [ ] **Step 1: Write failing issuer tests**

Add to `ansible_issuer/go/internal/vc/issuer_test.go`:

```go
func TestIssueZkIDMOICAOpenACCredentialOmitsNullifier(t *testing.T) {
	issuer := newTestIssuer(t)
	cred, err := issuer.IssueZkIDMOICAOpenAC("did:plc:abcdefghijklmnop", "commitment-1")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	subject := cred["credentialSubject"].(map[string]any)
	if subject["assuranceMethod"] != "moica_openac_zkid" {
		t.Fatalf("unexpected assurance method: %+v", subject)
	}
	if _, ok := subject["zkidNullifier"]; ok {
		t.Fatalf("credential leaked nullifier: %+v", subject)
	}
	if _, ok := subject["certificateSerialNumber"]; ok {
		t.Fatalf("credential leaked certificate serial: %+v", subject)
	}
}

func TestIssueZkIDMOICAOpenACRejectsDuplicateCommitment(t *testing.T) {
	issuer := newTestIssuer(t)
	if _, err := issuer.IssueZkIDMOICAOpenAC("did:plc:abcdefghijklmnop", "commitment-1"); err != nil {
		t.Fatalf("first issue: %v", err)
	}
	_, err := issuer.IssueZkIDMOICAOpenAC("did:plc:qrstuvwxyzabcd", "commitment-1")
	if err != ErrDuplicateActiveCredential {
		t.Fatalf("expected duplicate, got %v", err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./internal/vc
```

Expected: FAIL because `IssueZkIDMOICAOpenAC` does not exist.

- [ ] **Step 3: Add a dedicated issuance method**

Modify `ansible_issuer/go/internal/vc/issuer.go`:

```go
const (
	// existing constants remain unchanged
	zkIDMOICAAssuranceMethod = "moica_openac_zkid"
)

func (iss *Issuer) IssueZkIDMOICAOpenAC(holderDID, nullifierCommitment string) (map[string]any, error) {
	if err := iss.store.CheckDuplicate(nullifierCommitment); err != nil {
		return nil, err
	}

	return iss.issue(
		credentialType,
		CredentialSubject{
			ID:              holderDID,
			HumanVerified:   true,
			AssuranceLevel:  assuranceLevel,
			AssuranceMethod: zkIDMOICAAssuranceMethod,
			Jurisdiction:    jurisdiction,
		},
		nullifierCommitment,
		nullifierCommitment,
		"",
	)
}
```

Do not add any nullifier, certificate serial, legal name, national ID, or raw certificate field to `CredentialSubject`.

- [ ] **Step 4: Verify issuer tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./internal/vc
```

Expected: PASS.

## Task 4: Issuer zkID MOICA HTTP Flow

**Files:**

- Create: `ansible_issuer/go/internal/api/zkid_moica.go`
- Create: `ansible_issuer/go/internal/api/zkid_moica_test.go`
- Modify: `ansible_issuer/go/internal/api/handler.go`

- [ ] **Step 1: Write failing API tests**

Create `ansible_issuer/go/internal/api/zkid_moica_test.go`:

```go
package api_test

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/api"
	"github.com/trisaura/ansible_issuer/internal/provider"
)

type fakeZkIDVerifier struct {
	decision string
}

func (f fakeZkIDVerifier) Challenge(context.Context) (provider.ZkIDChallenge, error) {
	return provider.ZkIDChallenge{
		Challenge: "0xchallenge",
		AppID:     "4242",
		ExpiresAt: "2026-05-30T12:05:00Z",
	}, nil
}

func (f fakeZkIDVerifier) Status(context.Context) (provider.ZkIDVerifierStatus, error) {
	return provider.ZkIDVerifierStatus{
		SMTRoot:         "0xrevocationroot",
		AcceptedModulus: []string{"11", "22"},
	}, nil
}

func (f fakeZkIDVerifier) VerifyLinkedProof(context.Context, provider.ZkIDLinkedProofSubmission) (provider.ZkIDVerifyDecision, error) {
	return provider.ZkIDVerifyDecision{Decision: f.decision}, nil
}

func newZkIDHandler(t *testing.T) *api.Handler {
	t.Helper()
	h := newTestHandler(t)
	now := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	h.ConfigureZkIDMOICA(api.ZkIDMOICAConfig{
		SessionStore: provider.NewMemorySessionStore(func() time.Time { return now }),
		Verifier:     fakeZkIDVerifier{decision: "pass"},
		SnapshotURL:  "https://issuer.example/moica/smt-snapshot.bin",
		Now:          func() time.Time { return now },
	})
	return h
}

func TestZkIDMOICAFlowIssuesCredential(t *testing.T) {
	h := newZkIDHandler(t)

	challenge := call(h, http.MethodPost, "/api/v1/vc/zkid/moica/challenge", map[string]any{
		"did": testDID,
	})
	if challenge.Code != http.StatusOK {
		t.Fatalf("challenge failed: %d %s", challenge.Code, challenge.Body)
	}
	challengeBody := bodyJSON(t, challenge)
	offerID := challengeBody["offer_id"].(string)

	verify := call(h, http.MethodPost, "/api/v1/vc/zkid/moica/verify", map[string]any{
		"did":      testDID,
		"offer_id": offerID,
		"submission": map[string]any{
			"cert_chain": map[string]any{
				"proof": "cert-proof",
				"public_inputs": map[string]any{
					"pk_commit": "12345",
					"modulus":   []string{"11", "22"},
					"smt_root":  "0xrevocationroot",
				},
			},
			"device_sig": map[string]any{
				"proof": "device-proof",
				"public_inputs": map[string]any{
					"pk_commit":     "12345",
					"nullifier":     "0xappscopednullifier",
					"app_id_packed": "4242",
					"challenge":     "0xchallenge",
				},
			},
		},
	})
	if verify.Code != http.StatusOK {
		t.Fatalf("verify failed: %d %s", verify.Code, verify.Body)
	}

	issue := call(h, http.MethodPost, "/api/v1/vc/zkid/moica/issue", map[string]any{
		"did": testDID, "offer_id": offerID,
	})
	if issue.Code != http.StatusOK {
		t.Fatalf("issue failed: %d %s", issue.Code, issue.Body)
	}
	vc := bodyJSON(t, issue)["vc"].(map[string]any)
	subject := vc["credentialSubject"].(map[string]any)
	if subject["assuranceMethod"] != "moica_openac_zkid" {
		t.Fatalf("unexpected vc subject: %+v", subject)
	}
	if _, ok := subject["nullifier"]; ok {
		t.Fatalf("vc leaked nullifier: %+v", subject)
	}
}

func TestZkIDMOICARejectsChallengeMismatch(t *testing.T) {
	h := newZkIDHandler(t)
	challenge := call(h, http.MethodPost, "/api/v1/vc/zkid/moica/challenge", map[string]any{"did": testDID})
	offerID := bodyJSON(t, challenge)["offer_id"].(string)

	response := call(h, http.MethodPost, "/api/v1/vc/zkid/moica/verify", map[string]any{
		"did":      testDID,
		"offer_id": offerID,
		"submission": map[string]any{
			"cert_chain": map[string]any{
				"proof": "cert-proof",
				"public_inputs": map[string]any{
					"pk_commit": "12345",
					"modulus":   []string{"11", "22"},
					"smt_root":  "0xrevocationroot",
				},
			},
			"device_sig": map[string]any{
				"proof": "device-proof",
				"public_inputs": map[string]any{
					"pk_commit":     "12345",
					"nullifier":     "0xappscopednullifier",
					"app_id_packed": "4242",
					"challenge":     "0xwrong",
				},
			},
		},
	})
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected challenge rejection, got %d %s", response.Code, response.Body)
	}
	if bodyJSON(t, response)["error"] != "invalid_zkid_challenge" {
		t.Fatalf("unexpected error: %s", response.Body)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./internal/api
```

Expected: FAIL because the zkID API routes and configuration do not exist.

- [ ] **Step 3: Implement handler configuration and routes**

Modify `ansible_issuer/go/internal/api/handler.go`:

```go
type Handler struct {
	// existing fields remain
	zkidStore       provider.SessionStore
	zkidVerifier    provider.ZkIDVerifierClient
	zkidSnapshotURL string
	zkidNow         func() time.Time
}

func (h *Handler) Register(mux *http.ServeMux) {
	// existing routes remain
	mux.HandleFunc("POST /api/v1/vc/zkid/moica/challenge", h.zkidMOICAChallenge)
	mux.HandleFunc("POST /api/v1/vc/zkid/moica/verify", h.zkidMOICAVerify)
	mux.HandleFunc("GET /api/v1/vc/zkid/moica/status/{offer_id}", h.zkidMOICAStatus)
	mux.HandleFunc("POST /api/v1/vc/zkid/moica/issue", h.zkidMOICAIssue)
}
```

Create `ansible_issuer/go/internal/api/zkid_moica.go` with:

```go
package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/trisaura/ansible_issuer/internal/commitment"
	"github.com/trisaura/ansible_issuer/internal/provider"
	"github.com/trisaura/ansible_issuer/internal/vc"
)

const zkidMOICACommitmentContext = "zkid_moica_openac_v1"

type ZkIDMOICAConfig struct {
	SessionStore provider.SessionStore
	Verifier     provider.ZkIDVerifierClient
	SnapshotURL  string
	Now          func() time.Time
}

func (h *Handler) ConfigureZkIDMOICA(config ZkIDMOICAConfig) {
	h.zkidStore = config.SessionStore
	h.zkidVerifier = config.Verifier
	h.zkidSnapshotURL = config.SnapshotURL
	h.zkidNow = config.Now
	if h.zkidNow == nil {
		h.zkidNow = time.Now
	}
}

func (h *Handler) zkidMOICAChallenge(w http.ResponseWriter, r *http.Request) {
	if !h.zkidConfigured(w) {
		return
	}
	var body struct {
		DID string `json:"did"`
	}
	if !decodeJSON(w, r, &body) || !validateDID(w, body.DID) {
		return
	}
	challenge, err := h.zkidVerifier.Challenge(r.Context())
	if err != nil {
		writeError(w, http.StatusBadGateway, "zkid_verifier_unavailable")
		return
	}
	status, err := h.zkidVerifier.Status(r.Context())
	if err != nil {
		writeError(w, http.StatusBadGateway, "zkid_verifier_unavailable")
		return
	}
	expiresAt, err := time.Parse(time.RFC3339, challenge.ExpiresAt)
	if err != nil {
		writeError(w, http.StatusBadGateway, "invalid_zkid_challenge")
		return
	}
	offerID, err := randomToken()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "random_error")
		return
	}
	if err := h.zkidStore.CreateAuthSession(provider.AuthSession{
		OfferID:   offerID,
		DID:       body.DID,
		Email:     "zkid-moica@local.invalid",
		State:     challenge.Challenge,
		ExpiresAt: expiresAt,
	}); err != nil {
		writeError(w, http.StatusInternalServerError, "zkid_session_error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"offer_id":         offerID,
		"challenge":        challenge.Challenge,
		"app_id":           challenge.AppID,
		"expires_at":       challenge.ExpiresAt,
		"smt_root":         status.SMTRoot,
		"accepted_modulus": status.AcceptedModulus,
		"snapshot_url":     h.zkidSnapshotURL,
	})
}

func (h *Handler) zkidMOICAVerify(w http.ResponseWriter, r *http.Request) {
	if !h.zkidConfigured(w) {
		return
	}
	var body struct {
		DID        string                              `json:"did"`
		OfferID    string                              `json:"offer_id"`
		Submission provider.ZkIDLinkedProofSubmission `json:"submission"`
	}
	if !decodeJSON(w, r, &body) || !validateDID(w, body.DID) || !validateRequired(w, body.OfferID) {
		return
	}
	sessionReader, ok := h.zkidStore.(interface {
		GetAuthSessionByOfferID(string) (provider.AuthSession, error)
	})
	if !ok {
		writeError(w, http.StatusInternalServerError, "zkid_session_error")
		return
	}
	session, err := sessionReader.GetAuthSessionByOfferID(body.OfferID)
	if err != nil {
		writeError(w, http.StatusConflict, "zkid_session_not_found")
		return
	}
	if session.DID != body.DID {
		writeError(w, http.StatusUnauthorized, "state_mismatch")
		return
	}
	values, err := provider.ExtractZkIDPublicValues(body.Submission)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "invalid_zkid_submission")
		return
	}
	if values.Challenge != session.State {
		writeError(w, http.StatusUnauthorized, "invalid_zkid_challenge")
		return
	}
	decision, err := h.zkidVerifier.VerifyLinkedProof(r.Context(), body.Submission)
	if err != nil {
		writeError(w, http.StatusBadGateway, "zkid_verifier_unavailable")
		return
	}
	if decision.Decision != "pass" {
		writeError(w, http.StatusUnauthorized, "invalid_zkid_proof")
		return
	}
	commitmentContext := zkidMOICACommitmentContext + ":" + values.AppIDPacked
	subjectCommitment := commitment.Compute(h.pepper, values.Nullifier, commitmentContext)
	if err := h.zkidStore.StoreVerifiedSession(provider.VerifiedSession{
		OfferID:           session.OfferID,
		DID:               session.DID,
		Email:             session.Email,
		SubjectCommitment: subjectCommitment,
		VerifiedAt:        h.zkidNow(),
		ExpiresAt:         session.ExpiresAt,
	}); err != nil {
		writeError(w, http.StatusInternalServerError, "zkid_session_error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "verified", "offer_id": session.OfferID})
}

func (h *Handler) zkidMOICAStatus(w http.ResponseWriter, r *http.Request) {
	if !h.zkidConfigured(w) {
		return
	}
	offerID := r.PathValue("offer_id")
	if offerID == "" {
		writeError(w, http.StatusBadRequest, "missing_id")
		return
	}
	if _, err := h.zkidStore.GetVerifiedSession(offerID); err == nil {
		writeJSON(w, http.StatusOK, map[string]any{"status": "verified"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "pending"})
}

func (h *Handler) zkidMOICAIssue(w http.ResponseWriter, r *http.Request) {
	if !h.zkidConfigured(w) {
		return
	}
	var body struct {
		DID     string `json:"did"`
		OfferID string `json:"offer_id"`
	}
	if !decodeJSON(w, r, &body) || !validateDID(w, body.DID) || !validateRequired(w, body.OfferID) {
		return
	}
	verified, err := h.zkidStore.ConsumeVerifiedSession(body.OfferID)
	if err != nil {
		writeError(w, http.StatusConflict, "zkid_not_verified")
		return
	}
	if verified.DID != body.DID {
		writeError(w, http.StatusUnauthorized, "state_mismatch")
		return
	}
	credMap, err := h.issuer.IssueZkIDMOICAOpenAC(body.DID, verified.SubjectCommitment)
	if err != nil {
		if errors.Is(err, vc.ErrDuplicateActiveCredential) {
			writeError(w, http.StatusConflict, "duplicate_active_credential")
			return
		}
		writeError(w, http.StatusInternalServerError, "issuance_error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"vc": credMap})
}

func (h *Handler) zkidConfigured(w http.ResponseWriter) bool {
	if h.zkidStore == nil || h.zkidVerifier == nil {
		writeError(w, http.StatusServiceUnavailable, "zkid_moica_unconfigured")
		return false
	}
	return true
}
```

This implementation intentionally uses the existing session store with a non-routable placeholder email because the store currently requires `Email`; do not expose that placeholder to clients.

- [ ] **Step 4: Verify API tests**

Run:

```bash
cd ansible_issuer/go
go test -c -o /private/tmp/ansible_issuer_api.test ./internal/api
go test -count=1 ./internal/api
```

Expected: compile succeeds. On this local machine, `go test -count=1 ./internal/api` may still hit the known macOS dyld `missing LC_UUID load command` blocker from the compliance review; if that happens, keep the compile artifact command as the verification evidence.

## Task 5: Issuer Server Environment Wiring

**Files:**

- Modify: `ansible_issuer/go/cmd/server/main.go`
- Modify: `docs/deployment/tw_provider_issuer_deployment.md`
- Create: `docs/architecture/zkid_moica_forum_personhood.md`

- [ ] **Step 1: Write failing server config tests**

Add to `ansible_issuer/go/cmd/server/main_test.go`:

```go
func TestBuildZkIDMOICAConfigRequiresVerifierURLOutsideMockMode(t *testing.T) {
	t.Setenv("ZKID_MOICA_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "zkid.json"))
	_, err := buildZkIDMOICAConfigFromEnv(false, time.Now)
	if err == nil || !errors.Is(err, errZkIDMOICAConfigMissing) {
		t.Fatalf("expected missing config error, got %v", err)
	}
}

func TestBuildZkIDMOICAConfigAllowsMockDefaults(t *testing.T) {
	cfg, err := buildZkIDMOICAConfigFromEnv(true, time.Now)
	if err != nil {
		t.Fatalf("mock config: %v", err)
	}
	if cfg.SnapshotURL == "" {
		t.Fatalf("expected mock snapshot URL")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./cmd/server
```

Expected: FAIL because `buildZkIDMOICAConfigFromEnv` and `errZkIDMOICAConfigMissing` do not exist.

- [ ] **Step 3: Wire zkID config**

Modify `ansible_issuer/go/cmd/server/main.go`:

```go
var errZkIDMOICAConfigMissing = errors.New("zkID MOICA config missing")

func configureZkIDMOICA(handler *api.Handler, mockMode bool) {
	config, err := buildZkIDMOICAConfigFromEnv(mockMode, time.Now)
	if err != nil {
		log.Fatal(err)
	}
	handler.ConfigureZkIDMOICA(config)
	log.Printf("zkID MOICA verifier enabled")
}

func buildZkIDMOICAConfigFromEnv(mockMode bool, now func() time.Time) (api.ZkIDMOICAConfig, error) {
	required := []string{
		"ZKID_MOICA_SESSION_STORE_PATH",
		"ZKID_MOICA_VERIFIER_URL",
		"ZKID_MOICA_SNAPSHOT_URL",
	}
	missing := missingEnv(required)
	if len(missing) > 0 && !mockMode {
		return api.ZkIDMOICAConfig{}, fmt.Errorf("%w: %s", errZkIDMOICAConfigMissing, strings.Join(missing, ", "))
	}

	storePath := os.Getenv("ZKID_MOICA_SESSION_STORE_PATH")
	verifierURL := os.Getenv("ZKID_MOICA_VERIFIER_URL")
	snapshotURL := os.Getenv("ZKID_MOICA_SNAPSHOT_URL")
	if mockMode {
		if storePath == "" {
			storePath = filepath.Join(os.TempDir(), "ansible_issuer_zkid_moica_sessions.json")
		}
		if verifierURL == "" {
			verifierURL = "http://127.0.0.1:4099"
		}
		if snapshotURL == "" {
			snapshotURL = "https://issuer.example/dev/moica-smt-snapshot.bin"
		}
	}

	store, err := provider.NewFileSessionStore(storePath, now)
	if err != nil {
		return api.ZkIDMOICAConfig{}, fmt.Errorf("zkID MOICA session store init: %w", err)
	}

	return api.ZkIDMOICAConfig{
		SessionStore: store,
		Verifier:     provider.NewHTTPZkIDVerifierClient(verifierURL, http.DefaultClient),
		SnapshotURL:  snapshotURL,
		Now:          now,
	}, nil
}
```

Call `configureZkIDMOICA(handler, mockMode)` after `configureTWProvider(handler, mockMode)` in `main()`.

- [ ] **Step 4: Update docs**

Append to `docs/deployment/tw_provider_issuer_deployment.md`:

```markdown
## zkID MOICA Forum Personhood Environment

- `ZKID_MOICA_SESSION_STORE_PATH`: durable JSON session store path for zkID challenge and verified-session state.
- `ZKID_MOICA_VERIFIER_URL`: base URL of the zkID/OpenAC verifier exposing `/challenge`, `/link-verify`, `/smt-root/status`, and `/issuer-cert/status`.
- `ZKID_MOICA_SNAPSHOT_URL`: public URL for the revocation SMT snapshot that Wallets download locally before proof generation.

The Issuer stores only server-keyed commitments derived from zkID app-scoped nullifiers. It must not log or persist raw MOICA certificate contents, PINs, legal names, national IDs, certificate serial numbers, full provider assertions, or raw zkID nullifiers.
```

Create `docs/architecture/zkid_moica_forum_personhood.md`:

````markdown
# zkID MOICA Forum Personhood

## Scope

This document describes the first Tris-Aura integration of zkID/OpenAC MOICA
proof-of-personhood for forum trust-tier use. The flow is optional and does not
replace low-assurance account creation or private local Wallet use.

## Endpoint Sequence

```text
Wallet -> Issuer: POST /api/v1/vc/zkid/moica/challenge {did}
Issuer -> zkID verifier: POST /challenge
Issuer -> zkID verifier: GET /smt-root/status
Issuer -> zkID verifier: GET /issuer-cert/status
Issuer -> Wallet: {offer_id, challenge, app_id, smt_root, accepted_modulus, snapshot_url, expires_at}
Wallet: download revocation SMT snapshot locally
Wallet: generate CertChain and DeviceSig proofs locally
Wallet: show consent summary before network submission
Wallet -> Issuer: POST /api/v1/vc/zkid/moica/verify {did, offer_id, submission}
Issuer -> zkID verifier: POST /link-verify
Issuer: derive server-keyed commitment from app-scoped nullifier
Wallet -> Issuer: POST /api/v1/vc/zkid/moica/issue {did, offer_id}
Issuer -> Wallet: {vc}
Wallet -> Relay: present normal VP containing TrisAuraHumanityCredential
Relay -> Forum session: trust_tier becomes verified_human
```

## Privacy Rules

The Wallet must not send full MOICA certificate data, certificate PIN, legal
name, national ID, raw certificate serial, private key material, or provider
assertions to Tris-Aura services.

The Issuer may receive zkID proof public inputs, including the app-scoped
nullifier. The Issuer must immediately derive a server-keyed commitment and must
not store the raw nullifier in session state, issued credentials, logs, Relay
payloads, Forum Host payloads, or ordinary verifier presentations.

Forum Hosts receive only the Relay trust tier or a normal VP validation result.
They do not receive zkID proof material.

## First-Version Limitation

zkID v0.1 prevents duplicate verification per certificate/key/app nullifier. It
does not prove one-human-one-account across certificate renewal, physical card
versus TW FidO, or future credential profiles with different keys.

## Operational Dependencies

The Issuer depends on a configured zkID verifier exposing `/challenge`,
`/link-verify`, `/smt-root/status`, and `/issuer-cert/status`. The Wallet
depends on a reachable SMT snapshot URL and a platform prover implementation.
When the platform prover is unavailable, the Wallet must fail closed and show
that MOICA ZK verification is unavailable for this build.
````

- [ ] **Step 5: Verify server tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./cmd/server
```

Expected: PASS.

## Task 6: Wallet Issuer Client Methods

**Files:**

- Modify: `ansible_node/app/lib/services/vc_issuer_client.dart`
- Modify: `ansible_node/app/test/vc_issuer_client_test.dart`

- [ ] **Step 1: Write failing client tests**

Add tests to `ansible_node/app/test/vc_issuer_client_test.dart` covering:

```dart
test('starts zkID MOICA challenge', () async {
  final client = VcIssuerClient(
    baseUrl: 'http://issuer.test',
    client: MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/vc/zkid/moica/challenge');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['did'], 'did:plc:abcdefghijklmnop');
      return http.Response(jsonEncode({
        'offer_id': 'offer-1',
        'challenge': '0xchallenge',
        'app_id': '4242',
        'expires_at': '2026-05-30T12:05:00Z',
        'smt_root': '0xrevocationroot',
        'accepted_modulus': ['11', '22'],
        'snapshot_url': 'https://issuer.example/moica-smt.bin',
      }), 200);
    }),
  );

  final challenge = await client.startZkIDMOICAChallenge(
    did: 'did:plc:abcdefghijklmnop',
  );

  expect(challenge.offerId, 'offer-1');
  expect(challenge.challenge, '0xchallenge');
  expect(challenge.snapshotUrl.toString(), contains('moica-smt.bin'));
});

test('submits zkID MOICA proof and issues credential', () async {
  var callIndex = 0;
  final client = VcIssuerClient(
    baseUrl: 'http://issuer.test',
    client: MockClient((request) async {
      callIndex += 1;
      if (callIndex == 1) {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/vc/zkid/moica/verify');
        return http.Response(jsonEncode({
          'status': 'verified',
          'offer_id': 'offer-1',
        }), 200);
      }
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/vc/zkid/moica/issue');
      return http.Response(jsonEncode({
        'vc': {
          '@context': ['https://www.w3.org/ns/credentials/v2'],
          'id': 'urn:uuid:moica-zkid-vc',
          'type': ['VerifiableCredential', 'TrisAuraHumanityCredential'],
          'issuer': 'did:web:issuer.elix.cool',
          'validFrom': '2026-05-30T12:00:00Z',
          'validUntil': '2026-08-28T12:00:00Z',
          'credentialSubject': {
            'id': 'did:plc:abcdefghijklmnop',
            'humanVerified': true,
            'assuranceMethod': 'moica_openac_zkid',
          },
        },
      }), 200);
    }),
  );

  final status = await client.verifyZkIDMOICAProof(
    did: 'did:plc:abcdefghijklmnop',
    offerId: 'offer-1',
    submission: {
      'cert_chain': {'proof': 'cert-proof', 'public_inputs': {}},
      'device_sig': {'proof': 'device-proof', 'public_inputs': {}},
    },
  );
  final vc = await client.issueZkIDMOICACredential(
    did: 'did:plc:abcdefghijklmnop',
    offerId: 'offer-1',
  );

  expect(status.status, 'verified');
  expect(vc['credentialSubject']['assuranceMethod'], 'moica_openac_zkid');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_node/app
flutter test test/vc_issuer_client_test.dart
```

Expected: FAIL because the models and methods do not exist.

- [ ] **Step 3: Add models and client methods**

Modify `ansible_node/app/lib/services/vc_issuer_client.dart`:

```dart
class ZkIDMOICAChallenge {
  final String offerId;
  final String challenge;
  final String appId;
  final DateTime expiresAt;
  final String smtRoot;
  final List<String> acceptedModulus;
  final Uri snapshotUrl;

  const ZkIDMOICAChallenge({
    required this.offerId,
    required this.challenge,
    required this.appId,
    required this.expiresAt,
    required this.smtRoot,
    required this.acceptedModulus,
    required this.snapshotUrl,
  });

  factory ZkIDMOICAChallenge.fromJson(Map<String, dynamic> json) {
    final modulus = json['accepted_modulus'];
    return ZkIDMOICAChallenge(
      offerId: json['offer_id'] as String,
      challenge: json['challenge'] as String,
      appId: json['app_id'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      smtRoot: json['smt_root'] as String,
      acceptedModulus: modulus is List ? modulus.whereType<String>().toList() : const [],
      snapshotUrl: Uri.parse(json['snapshot_url'] as String),
    );
  }
}

class ZkIDMOICAVerifyStatus {
  final String status;
  const ZkIDMOICAVerifyStatus({required this.status});
  bool get isVerified => status == 'verified';
}
```

Add methods:

```dart
Future<ZkIDMOICAChallenge> startZkIDMOICAChallenge({
  required String did,
}) async {
  final body = await _postJson('/api/v1/vc/zkid/moica/challenge', {
    'did': did,
  });
  return ZkIDMOICAChallenge.fromJson(body);
}

Future<ZkIDMOICAVerifyStatus> verifyZkIDMOICAProof({
  required String did,
  required String offerId,
  required Map<String, dynamic> submission,
}) async {
  final body = await _postJson('/api/v1/vc/zkid/moica/verify', {
    'did': did,
    'offer_id': offerId,
    'submission': submission,
  });
  return ZkIDMOICAVerifyStatus(status: body['status'] as String? ?? 'unknown');
}

Future<Map<String, dynamic>> issueZkIDMOICACredential({
  required String did,
  required String offerId,
}) async {
  final body = await _postJson('/api/v1/vc/zkid/moica/issue', {
    'did': did,
    'offer_id': offerId,
  });
  return body['vc'] as Map<String, dynamic>;
}
```

- [ ] **Step 4: Verify client tests**

Run:

```bash
cd ansible_node/app
flutter test test/vc_issuer_client_test.dart
```

Expected: PASS.

## Task 7: Wallet TW FidO zkID MOICA Production Prover

**Files:**

- Create: `ansible_node/app/lib/services/zkid_moica_prover.dart`
- Create: `ansible_node/app/test/zkid_moica_credential_screen_test.dart`
- Modify: `ansible_node/app/ios/Runner/AppDelegate.swift`
- Modify: `ansible_node/app/ios/Runner/Info.plist`
- Modify: `ansible_node/app/android/app/src/main/kotlin/io/trisaura/ansible_node/MainActivity.kt`
- Modify: `ansible_node/app/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Write failing TW FidO prover tests**

In `ansible_node/app/test/zkid_moica_credential_screen_test.dart`, add service tests that prove the production Dart prover invokes the native TW FidO/zkID channel and returns the linked proof envelope:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

test('TW FidO zkID prover calls native channel and returns linked proof', () async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  const channel = MethodChannel('ansible_node/zkid_moica');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        expect(call.method, 'generateTwFidoProof');
        final args = Map<String, Object?>.from(call.arguments as Map);
        expect(args['challenge'], '0xchallenge');
        expect(args['app_id'], '4242');
        expect(args['smt_root'], '0xrevocationroot');
        expect(args['snapshot_url'], 'https://issuer.example/moica-smt.bin');
        return {
          'cert_chain': {
            'proof': 'cert-proof',
            'public_inputs': {
              'pk_commit': '12345',
              'modulus': ['11', '22'],
              'smt_root': '0xrevocationroot',
            },
          },
          'device_sig': {
            'proof': 'device-proof',
            'public_inputs': {
              'pk_commit': '12345',
              'nullifier': '0xappscopednullifier',
              'app_id_packed': '4242',
              'challenge': '0xchallenge',
            },
          },
        };
      });

  final prover = TwFidoZkIDMOICAProver(channel: channel);
  final proof = await prover.generate(
    challenge: ZkIDMOICAChallenge(
      offerId: 'offer-1',
      challenge: '0xchallenge',
      appId: '4242',
      expiresAt: DateTime.utc(2026, 5, 30, 12, 5),
      smtRoot: '0xrevocationroot',
      acceptedModulus: ['11', '22'],
      snapshotUrl: Uri.parse('https://issuer.example/moica-smt.bin'),
    ),
  );

  expect(proof.submission['cert_chain'], isA<Map<String, dynamic>>());
  expect(proof.submission['device_sig'], isA<Map<String, dynamic>>());
  expect(proof.publicSummary.nullifierPresent, isTrue);
  expect(calls, hasLength(1));

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
});

test('TW FidO zkID prover maps native cancellation to a user-safe error', () async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ansible_node/zkid_moica');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'tw_fido_cancelled',
          message: 'User cancelled TW FidO authentication.',
        );
      });

  final prover = TwFidoZkIDMOICAProver(channel: channel);

  expect(
    () => prover.generate(
      challenge: ZkIDMOICAChallenge(
        offerId: 'offer-1',
        challenge: '0xchallenge',
        appId: '4242',
        expiresAt: DateTime.utc(2026, 5, 30, 12, 5),
        smtRoot: '0xrevocationroot',
        acceptedModulus: const ['11', '22'],
        snapshotUrl: Uri.parse('https://issuer.example/moica-smt.bin'),
      ),
    ),
    throwsA(isA<ZkIDMOICAProverException>().having(
      (error) => error.code,
      'code',
      'tw_fido_cancelled',
    )),
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_node/app
flutter test test/zkid_moica_credential_screen_test.dart
```

Expected: FAIL because `TwFidoZkIDMOICAProver`, `ZkIDMOICAProverException`, and the native channel contract do not exist.

- [ ] **Step 3: Implement the Dart TW FidO prover**

Create `ansible_node/app/lib/services/zkid_moica_prover.dart`:

```dart
import 'package:flutter/services.dart';

import 'vc_issuer_client.dart';

class ZkIDMOICAProofResult {
  final Map<String, dynamic> submission;
  final ZkIDMOICAProofPublicSummary publicSummary;

  const ZkIDMOICAProofResult({
    required this.submission,
    required this.publicSummary,
  });
}

class ZkIDMOICAProofPublicSummary {
  final bool nullifierPresent;
  final String smtRoot;
  final String appId;

  const ZkIDMOICAProofPublicSummary({
    required this.nullifierPresent,
    required this.smtRoot,
    required this.appId,
  });
}

abstract class ZkIDMOICAProver {
  Future<ZkIDMOICAProofResult> generate({
    required ZkIDMOICAChallenge challenge,
  });
}

class ZkIDMOICAProverException implements Exception {
  final String code;
  final String message;

  const ZkIDMOICAProverException(this.code, this.message);

  @override
  String toString() => 'ZkIDMOICAProverException($code): $message';
}

class TwFidoZkIDMOICAProver implements ZkIDMOICAProver {
  static const MethodChannel defaultChannel =
      MethodChannel('ansible_node/zkid_moica');

  final MethodChannel channel;

  const TwFidoZkIDMOICAProver({this.channel = defaultChannel});

  @override
  Future<ZkIDMOICAProofResult> generate({
    required ZkIDMOICAChallenge challenge,
  }) async {
    final raw;
    try {
      raw = await channel.invokeMapMethod<String, Object?>(
        'generateTwFidoProof',
        {
          'offer_id': challenge.offerId,
          'challenge': challenge.challenge,
          'app_id': challenge.appId,
          'expires_at': challenge.expiresAt.toIso8601String(),
          'smt_root': challenge.smtRoot,
          'accepted_modulus': challenge.acceptedModulus,
          'snapshot_url': challenge.snapshotUrl.toString(),
        },
      );
    } on PlatformException catch (error) {
      throw ZkIDMOICAProverException(
        error.code,
        error.message ?? 'TW FidO verification did not complete.',
      );
    }
    if (raw == null) {
      throw const ZkIDMOICAProverException(
        'missing_native_result',
        'TW FidO verification returned no proof.',
      );
    }
    final submission = _stringKeyedMap(raw);
    final deviceSig = _stringKeyedMap(submission['device_sig']);
    final publicInputs = _stringKeyedMap(deviceSig['public_inputs']);
    return ZkIDMOICAProofResult(
      submission: submission,
      publicSummary: ZkIDMOICAProofPublicSummary(
        nullifierPresent: publicInputs['nullifier'] is String &&
            (publicInputs['nullifier'] as String).isNotEmpty,
        smtRoot: challenge.smtRoot,
        appId: challenge.appId,
      ),
    );
  }
}

Map<String, dynamic> _stringKeyedMap(Object? value) {
  if (value is Map) {
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }
  throw const ZkIDMOICAProverException(
    'invalid_native_result',
    'TW FidO verification returned an invalid proof.',
  );
}
```

- [ ] **Step 4: Wire the iOS native channel**

Modify `ansible_node/app/ios/Runner/AppDelegate.swift` to register a new method channel in `application(_:didFinishLaunchingWithOptions:)`:

```swift
GeneratedPluginRegistrant.register(with: self)
registerBackupPolicyChannel()
registerEmbeddingChannel()
registerZkIDMOICAChannel()
```

Add this method to `AppDelegate`:

```swift
private func registerZkIDMOICAChannel() {
  guard let controller = window?.rootViewController as? FlutterViewController else {
    return
  }
  let channel = FlutterMethodChannel(
    name: "ansible_node/zkid_moica",
    binaryMessenger: controller.binaryMessenger
  )
  channel.setMethodCallHandler { call, result in
    guard call.method == "generateTwFidoProof" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let challenge = args["challenge"] as? String,
      let appID = args["app_id"] as? String,
      let smtRoot = args["smt_root"] as? String,
      let snapshotURL = args["snapshot_url"] as? String
    else {
      result(FlutterError(
        code: "invalid_arguments",
        message: "Missing zkID MOICA proof arguments.",
        details: nil
      ))
      return
    }

    Task {
      do {
        let proof = try await TwFidoZkIDMOICAProofService().generateProof(
          challenge: challenge,
          appID: appID,
          smtRoot: smtRoot,
          snapshotURL: snapshotURL
        )
        result(proof)
      } catch TwFidoZkIDMOICAError.cancelled {
        result(FlutterError(
          code: "tw_fido_cancelled",
          message: "User cancelled TW FidO authentication.",
          details: nil
        ))
      } catch {
        result(FlutterError(
          code: "tw_fido_proof_failed",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
  }
}
```

Add `TwFidoZkIDMOICAProofService` in the same file or a new Swift file already included in the Runner target. It must call the zkID/Mopro iOS binding that supports TW FidO, open the TW FidO deep link/request flow, wait for the callback into Elix, generate the CertChain and DeviceSig proofs, and return exactly this dictionary shape:

```swift
[
  "cert_chain": [
    "proof": certChainProof,
    "public_inputs": [
      "pk_commit": pkCommit,
      "modulus": acceptedModulus,
      "smt_root": smtRoot
    ]
  ],
  "device_sig": [
    "proof": deviceSigProof,
    "public_inputs": [
      "pk_commit": pkCommit,
      "nullifier": nullifier,
      "app_id_packed": appIDPacked,
      "challenge": challenge
    ]
  ]
]
```

Modify `ansible_node/app/ios/Runner/Info.plist` to allow opening TW FidO and returning to Elix:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>io.trisaura.elix</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>trisaura</string>
    </array>
  </dict>
</array>
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>mobilemoica</string>
</array>
```

The provided APP2APP notes use the `mobilemoica://.../a2a/verifySign` scheme.
If approved UAT or production documents differ, update both
`LSApplicationQueriesSchemes` and `TwFidoZkIDMOICAProofService`.

- [ ] **Step 5: Wire the Android native channel**

Modify `ansible_node/app/android/app/src/main/kotlin/io/trisaura/ansible_node/MainActivity.kt` to add a second `MethodChannel` in `configureFlutterEngine`:

```kotlin
MethodChannel(
    flutterEngine.dartExecutor.binaryMessenger,
    "ansible_node/zkid_moica"
).setMethodCallHandler { call, result ->
    when (call.method) {
        "generateTwFidoProof" -> {
            val challenge = call.argument<String>("challenge")
            val appId = call.argument<String>("app_id")
            val smtRoot = call.argument<String>("smt_root")
            val snapshotUrl = call.argument<String>("snapshot_url")
            if (challenge.isNullOrBlank() ||
                appId.isNullOrBlank() ||
                smtRoot.isNullOrBlank() ||
                snapshotUrl.isNullOrBlank()
            ) {
                result.error(
                    "invalid_arguments",
                    "Missing zkID MOICA proof arguments.",
                    null
                )
                return@setMethodCallHandler
            }
            TwFidoZkIDMOICAProofService(this).generateProof(
                challenge = challenge,
                appId = appId,
                smtRoot = smtRoot,
                snapshotUrl = snapshotUrl,
                onSuccess = { proof -> result.success(proof) },
                onCancel = {
                    result.error(
                        "tw_fido_cancelled",
                        "User cancelled TW FidO authentication.",
                        null
                    )
                },
                onError = { error ->
                    result.error(
                        "tw_fido_proof_failed",
                        error.message ?: "TW FidO proof generation failed.",
                        null
                    )
                }
            )
        }
        else -> result.notImplemented()
    }
}
```

Add `TwFidoZkIDMOICAProofService` in `ansible_node/app/android/app/src/main/kotlin/io/trisaura/ansible_node/`. It must call the zkID/Mopro Android binding that supports TW FidO, open the TW FidO deep link/request flow, wait for the callback into Elix, generate the CertChain and DeviceSig proofs, and return the same `cert_chain` / `device_sig` map shape used by iOS.

Modify `ansible_node/app/android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="trisaura" android:host="zkid" android:pathPrefix="/moica/callback" />
</intent-filter>
```

Add scheme visibility for the TW FidO app:

```xml
<queries>
    <intent>
        <action android:name="android.intent.action.VIEW" />
        <data android:scheme="mobilemoica" />
    </intent>
</queries>
```

Do not hard-code an Android package name unless it is confirmed by approved TW
FidO documentation. If the official UAT or production scheme differs, update the
manifest and `TwFidoZkIDMOICAProofService`.

- [ ] **Step 6: Verify prover tests**

Run:

```bash
cd ansible_node/app
flutter test test/zkid_moica_credential_screen_test.dart
```

Expected: PASS for the Dart channel-contract tests.

- [ ] **Step 7: True-device acceptance test**

Run on at least one iOS or Android physical device that has the production or UAT TW FidO app installed and enrolled:

```bash
cd ansible_node/app
flutter run -d <physical-device-id>
```

Expected result:

- In Elix, select `自然人憑證 ZK`.
- Tap `產生本機證明`.
- Elix opens the TW FidO app through the configured deep link/request flow.
- User completes TW FidO authentication.
- Control returns to Elix.
- Elix generates a zkID linked proof with non-empty `cert_chain`, `device_sig`, and `device_sig.public_inputs.nullifier`.
- User taps `同意送出證明`.
- Issuer verifies the proof and `/api/v1/vc/zkid/moica/issue` returns a `TrisAuraHumanityCredential`.
- Wallet stores the VC with display name `MOICA Verified Human`.
- No UI, logs, or stored credential payload expose legal name, national ID, raw certificate serial, PIN, provider assertion, or raw certificate data.

## Task 8: Wallet zkID MOICA UI With Explicit Consent

**Files:**

- Create: `ansible_node/app/lib/screens/zkid_moica_credential_screen.dart`
- Modify: `ansible_node/app/lib/screens/credential_issuance_wizard.dart`
- Modify: `ansible_node/app/test/zkid_moica_credential_screen_test.dart`

- [ ] **Step 1: Write failing UI tests**

Add widget tests:

```dart
testWidgets('zkID MOICA panel requires consent before submitting proof', (tester) async {
  final repo = InMemoryWalletRepository();
  final client = FakeZkIDMOICAIssuerClient();

  await tester.pumpWidget(MaterialApp(
    home: ZkIDMOICACredentialPanel(
      holderDid: 'did:plc:abcdefghijklmnop',
      vcIssuerClient: client,
      prover: const FakeZkIDMOICAProver(),
      walletRepository: repo,
    ),
  ));

  await tester.tap(find.text('產生本機證明'));
  await tester.pump();

  expect(find.text('不會送出姓名、身分證字號、PIN 或完整自然人憑證'), findsOneWidget);
  expect(client.verifyCalled, isFalse);

  await tester.tap(find.text('同意送出證明'));
  await tester.pump();

  expect(client.verifyCalled, isTrue);
  expect(client.issueCalled, isTrue);
  expect(find.text('自然人憑證驗證已加入 Wallet'), findsOneWidget);
});

testWidgets('zkID MOICA panel stores credential with MOICA display name', (tester) async {
  final repo = InMemoryWalletRepository();
  await tester.pumpWidget(MaterialApp(
    home: ZkIDMOICACredentialPanel(
      holderDid: 'did:plc:abcdefghijklmnop',
      vcIssuerClient: FakeZkIDMOICAIssuerClient(),
      prover: const FakeZkIDMOICAProver(),
      walletRepository: repo,
    ),
  ));

  await tester.tap(find.text('產生本機證明'));
  await tester.pump();
  await tester.tap(find.text('同意送出證明'));
  await tester.pump();

  final credentials = await repo.listCredentials();
  expect(credentials.single.displayName, 'MOICA Verified Human');
});

class FakeZkIDMOICAProver implements ZkIDMOICAProver {
  const FakeZkIDMOICAProver();

  @override
  Future<ZkIDMOICAProofResult> generate({
    required ZkIDMOICAChallenge challenge,
  }) async {
    return ZkIDMOICAProofResult(
      submission: {
        'cert_chain': {
          'proof': 'cert-proof',
          'public_inputs': {
            'pk_commit': '12345',
            'modulus': challenge.acceptedModulus,
            'smt_root': challenge.smtRoot,
          },
        },
        'device_sig': {
          'proof': 'device-proof',
          'public_inputs': {
            'pk_commit': '12345',
            'nullifier': '0xappscopednullifier',
            'app_id_packed': challenge.appId,
            'challenge': challenge.challenge,
          },
        },
      },
      publicSummary: ZkIDMOICAProofPublicSummary(
        nullifierPresent: true,
        smtRoot: challenge.smtRoot,
        appId: challenge.appId,
      ),
    );
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_node/app
flutter test test/zkid_moica_credential_screen_test.dart
```

Expected: FAIL because `ZkIDMOICACredentialPanel` does not exist.

- [ ] **Step 3: Implement the panel**

Create `ansible_node/app/lib/screens/zkid_moica_credential_screen.dart` using the same storage pattern as `PassportNfcCredentialPanel`:

```dart
enum ZkIDMOICAPhase { idle, preparing, consent, submitting, done, error }
```

The action flow must be:

1. Call `startZkIDMOICAChallenge(did: holderDid)`.
2. Call `prover.generate(challenge: challenge)` locally. The default production prover must be `const TwFidoZkIDMOICAProver()`.
3. Show a consent state with this exact user-facing privacy sentence:

```dart
const Text('不會送出姓名、身分證字號、PIN 或完整自然人憑證')
```

4. Only after the user taps `同意送出證明`, call `verifyZkIDMOICAProof`.
5. Call `issueZkIDMOICACredential`.
6. Parse with `TrisAuraCredential.fromJson`.
7. Require `credential.claims['assuranceMethod'] == 'moica_openac_zkid'`.
8. Store through `WalletRepository.saveCredential` with display name `MOICA Verified Human`.

Reuse `SecureCredentialPayloadCodec` so the raw VC payload remains encrypted in local storage.

- [ ] **Step 4: Add wizard option**

Modify `ansible_node/app/lib/screens/credential_issuance_wizard.dart`:

```dart
enum CredentialIssuanceFlow { zkidMoica, twProvider, passportNfc, emailOtp }
```

Add a button:

```dart
_FlowOptionButton(
  icon: Icons.badge_outlined,
  label: '自然人憑證 ZK',
  selected: _selectedFlow == CredentialIssuanceFlow.zkidMoica,
  onTap: () => _select(CredentialIssuanceFlow.zkidMoica),
),
```

Add a switch branch that returns `ZkIDMOICACredentialPanel`.

- [ ] **Step 5: Verify UI tests**

Run:

```bash
cd ansible_node/app
flutter test test/zkid_moica_credential_screen_test.dart test/credential_issuance_wizard_test.dart
```

Expected: PASS.

## Task 9: Relay VC Privacy Guard And Reputation Mapping

**Files:**

- Modify: `ansible_relay/phoenix/lib/ansible_relay/vp_verifier.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/reputation_controller.ex`
- Modify: `ansible_relay/phoenix/test/vp_verifier_test.exs`
- Modify: `ansible_relay/phoenix/test/reputation_controller_test.exs`

- [ ] **Step 1: Write failing Relay privacy tests**

Add tests to `ansible_relay/phoenix/test/vp_verifier_test.exs`:

```elixir
test "rejects humanity credential that leaks zkID nullifier" do
  vp = signed_vp_with_credential(%{
    "type" => ["VerifiableCredential", "TrisAuraHumanityCredential"],
    "credentialSubject" => %{
      "id" => @holder_did,
      "humanVerified" => true,
      "assuranceMethod" => "moica_openac_zkid",
      "zkidNullifier" => "0xleaked"
    }
  })

  assert {:error, :prohibited_vc_claim} = VpVerifier.verify(@holder_did, vp)
end

test "accepts zkID MOICA humanity credential without raw identity claims" do
  vp = signed_vp_with_credential(%{
    "type" => ["VerifiableCredential", "TrisAuraHumanityCredential"],
    "credentialSubject" => %{
      "id" => @holder_did,
      "humanVerified" => true,
      "assuranceLevel" => "tw_natural_person_certificate",
      "assuranceMethod" => "moica_openac_zkid",
      "jurisdiction" => "TW"
    }
  })

  assert {:ok, "TrisAuraHumanityCredential"} = VpVerifier.verify(@holder_did, vp)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_relay/phoenix
mix test test/vp_verifier_test.exs test/reputation_controller_test.exs
```

Expected: FAIL because the privacy guard does not exist.

- [ ] **Step 3: Add prohibited claim validation**

Modify `ansible_relay/phoenix/lib/ansible_relay/vp_verifier.ex`:

```elixir
@prohibited_vc_claims MapSet.new([
  "nationalId",
  "legalName",
  "birthDate",
  "householdRegistrationAddress",
  "certificateSerialNumber",
  "certificateSerial",
  "phone",
  "email",
  "rawProviderAssertion",
  "documentNumber",
  "passportNumber",
  "passportLocalUniqueId",
  "passportUid",
  "passport_uid",
  "nationalIdHash",
  "national_id_hash",
  "passportNumberHash",
  "passport_number_hash",
  "rawMrz",
  "rawMRZ",
  "dg1",
  "dg2",
  "sod",
  "faceImage",
  "nullifier",
  "zkidNullifier",
  "appScopedNullifier"
])
```

Call `check_vc_privacy(vc)` inside `validate_vc/2` before issuer proof verification:

```elixir
defp validate_vc(vc, holder_did) do
  with :ok <- check_vc_subject(vc, holder_did),
       :ok <- check_vc_type(vc),
       :ok <- check_vc_privacy(vc),
       :ok <- check_vc_expiry(vc),
       :ok <- verify_vc_issuer_proof(vc) do
    :ok
  end
end

defp check_vc_privacy(vc) do
  subject = Map.get(vc, "credentialSubject", %{})
  case find_prohibited_claim(subject) do
    nil -> :ok
    _claim -> {:error, :prohibited_vc_claim}
  end
end

defp find_prohibited_claim(value) when is_map(value) do
  Enum.find_value(value, fn {key, nested} ->
    if MapSet.member?(@prohibited_vc_claims, to_string(key)) do
      to_string(key)
    else
      find_prohibited_claim(nested)
    end
  end)
end

defp find_prohibited_claim(value) when is_list(value),
  do: Enum.find_value(value, &find_prohibited_claim/1)

defp find_prohibited_claim(_value), do: nil
```

Add `:prohibited_vc_claim` to the `@type error` union. In `ReputationController.present/2`, map `{:error, :prohibited_vc_claim}` to:

```elixir
send_json(conn, 401, %{error: "invalid_vc"})
```

- [ ] **Step 4: Verify Relay tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/vp_verifier_test.exs test/reputation_controller_test.exs
```

Expected: PASS.

## Task 10: Web Session Trust Tier Propagation For Forum UX

**Files:**

- Modify: `ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex`
- Modify: `ansible_relay/phoenix/lib/ansible_relay/web/controllers/web_session_controller.ex`
- Modify: `ansible_relay/phoenix/test/web_session_controller_test.exs`
- Modify: `ansible_distribution_frontend/test/forum_login_app.test.mjs`

- [ ] **Step 1: Write failing Relay web-session tests**

Add a test proving a DID with Relay reputation `verified_human` receives a web session with the same trust tier:

```elixir
test "approved web session inherits verified human trust tier", %{conn: conn} do
  seed_verified_did(@holder_did, reputation_tier: "verified_human")
  challenge = create_web_session_challenge(conn)
  grant = signed_web_session_grant(challenge, @holder_did)

  response =
    conn
    |> post("/api/v1/web-sessions/approve", %{
      "challenge_id" => challenge["challenge_id"],
      "subject_did" => @holder_did,
      "grant" => grant.payload,
      "signature" => grant.signature
    })
    |> json_response(200)

  assert response["trust_tier"] == "verified_human"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd ansible_relay/phoenix
mix test test/web_session_controller_test.exs
```

Expected: FAIL because `WebSessionStore` hardcodes `self_custody_did`.

- [ ] **Step 3: Let approved sessions accept a trust tier**

Modify `ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex`:

```elixir
@default_trust_tier "self_custody_did"

trust_tier = atom_attr(attrs, :trust_tier, @default_trust_tier)

session = %{
  session_token: token("wst"),
  subject_did: subject_did,
  approving_device_id: approving_device_id,
  web_origin: challenge.web_origin,
  relay_origin: challenge.relay_origin,
  scopes: scopes,
  trust_tier: trust_tier,
  expires_at: expires_at,
  created_at: now,
  revoked_at: nil
}
```

Modify `WebSessionController.approve/2` to compute:

```elixir
trust_tier = trust_tier_for(subject_did)
```

and pass `trust_tier: trust_tier` into `WebSessionStore.approve_challenge/2`.

Add helper:

```elixir
defp trust_tier_for(did) do
  case AnsibleRelay.DidAccountCache.get(did) do
    {:ok, %{reputation_tier: tier}} when tier in ["verified_human", "dns_verified", "basic"] ->
      tier

    _ ->
      "self_custody_did"
  end
end
```

- [ ] **Step 4: Verify frontend smoke test**

Update `ansible_distribution_frontend/test/forum_login_app.test.mjs` so the mocked challenge approval returns `trust_tier: "verified_human"` and assert the controller state preserves it:

```js
assert.equal(state.trustTier, 'verified_human');
```

Run:

```bash
cd ansible_distribution_frontend
npm test -- test/forum_login_app.test.mjs
```

Expected: PASS.

- [ ] **Step 5: Verify Relay tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/web_session_controller_test.exs
```

Expected: PASS.

## Task 11: End-To-End Verification Commands

**Files:**

- No code changes in this task.

- [ ] **Step 1: Run focused Go tests**

Run:

```bash
cd ansible_issuer/go
go test -count=1 ./internal/provider ./internal/vc ./cmd/server
go test -c -o /private/tmp/ansible_issuer_api.test ./internal/api
go test -count=1 ./internal/api
```

Expected: provider, vc, and server tests pass. API package compiles. If `go test -count=1 ./internal/api` hits the known local dyld blocker, record the exact error and keep the compile artifact as evidence.

- [ ] **Step 2: Run focused Flutter tests**

Run:

```bash
cd ansible_node/app
flutter analyze lib/services/vc_issuer_client.dart lib/services/zkid_moica_prover.dart lib/screens/zkid_moica_credential_screen.dart lib/screens/credential_issuance_wizard.dart test/vc_issuer_client_test.dart test/zkid_moica_credential_screen_test.dart test/credential_issuance_wizard_test.dart
flutter test test/vc_issuer_client_test.dart test/zkid_moica_credential_screen_test.dart test/credential_issuance_wizard_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run focused Relay tests**

Run:

```bash
cd ansible_relay/phoenix
mix test test/vp_verifier_test.exs test/reputation_controller_test.exs test/web_session_controller_test.exs
```

Expected: PASS.

- [ ] **Step 4: Run frontend smoke test**

Run:

```bash
cd ansible_distribution_frontend
npm test -- test/forum_login_app.test.mjs
```

Expected: PASS.

- [ ] **Step 5: Run TW FidO true-device acceptance**

Run on a physical iOS or Android device with TW FidO installed and enrolled:

```bash
cd ansible_node/app
flutter run -d <physical-device-id>
```

Expected: Elix opens TW FidO from the `自然人憑證 ZK` flow, returns to Elix after authentication, generates a zkID linked proof, submits it after explicit consent, receives a `TrisAuraHumanityCredential` from `/api/v1/vc/zkid/moica/issue`, and stores it as `MOICA Verified Human`.

## Task 12: Commit Boundaries

Use these commits:

```bash
git add ansible_issuer/go/internal/provider ansible_issuer/go/internal/api ansible_issuer/go/internal/vc ansible_issuer/go/cmd/server docs/architecture/zkid_moica_forum_personhood.md docs/deployment/tw_provider_issuer_deployment.md
git commit -m "feat: add issuer zkid moica personhood flow"
```

```bash
git add ansible_node/app/lib/services/vc_issuer_client.dart ansible_node/app/lib/services/zkid_moica_prover.dart ansible_node/app/lib/screens/zkid_moica_credential_screen.dart ansible_node/app/lib/screens/credential_issuance_wizard.dart ansible_node/app/ios/Runner/AppDelegate.swift ansible_node/app/ios/Runner/Info.plist ansible_node/app/android/app/src/main/kotlin/io/trisaura/ansible_node/MainActivity.kt ansible_node/app/android/app/src/main/AndroidManifest.xml ansible_node/app/test/vc_issuer_client_test.dart ansible_node/app/test/zkid_moica_credential_screen_test.dart
git commit -m "feat: add wallet zkid moica verification flow"
```

```bash
git add ansible_relay/phoenix/lib/ansible_relay/vp_verifier.ex ansible_relay/phoenix/lib/ansible_relay/web_session_store.ex ansible_relay/phoenix/lib/ansible_relay/web/controllers/reputation_controller.ex ansible_relay/phoenix/lib/ansible_relay/web/controllers/web_session_controller.ex ansible_relay/phoenix/test/vp_verifier_test.exs ansible_relay/phoenix/test/reputation_controller_test.exs ansible_relay/phoenix/test/web_session_controller_test.exs ansible_distribution_frontend/test/forum_login_app.test.mjs
git commit -m "feat: propagate verified human trust to forum sessions"
```

## First-Version Non-Goals

- No on-chain verifier.
- No storage or disclosure of raw MOICA certificate contents.
- No storage or disclosure of raw zkID nullifiers outside the transient verification request.
- No claim that this proves strict one-human-one-account across TW FidO re-enrollment, certificate renewal, physical card credentials, or other credential profiles.
- No requirement that ordinary private app use must complete MOICA verification.
- No requirement that external Forum Hosts trust this credential unless their compliance and trust policy says so.
