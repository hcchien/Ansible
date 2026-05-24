# Passport Wallet Credential Extension Design

## Goal

Add ePassport NFC as an optional Wallet verification path after Passkeys
registration. The feature issues and stores a W3C VC v2.0-compatible Wallet
credential while preserving the V2 product boundary: passports are not an
account creation gate, and raw passport numbers never leave the device.

## Product Position

Passport verification is a progressive trust upgrade. A user can keep using the
app with the existing Passkeys identity and may later add a passport-backed
credential from Wallet. Communities and relays can treat the resulting
credential as a higher assurance signal, but the first implementation does not
claim global uniqueness or one-passport-one-account Sybil resistance.

The first supported credential type remains a `TrisAuraHumanityCredential`.
Passport NFC is represented as a new assurance method on that credential, not
as a replacement for the account DID or passkey.

## W3C Credential Baseline

The Passport Wallet path uses W3C Verifiable Credentials Data Model v2.0 as the
current baseline:

- `@context` includes `https://www.w3.org/ns/credentials/v2` and a Tris-Aura
  context for custom claims.
- `type` includes `VerifiableCredential` and `TrisAuraHumanityCredential`.
- `issuer` is the Tris-Aura issuer DID.
- `validFrom` and `validUntil` are used instead of the v1.1-era
  `issuanceDate` and `expirationDate`.
- `credentialSubject.id` is the holder DID.
- `credentialSubject` contains only the claims needed by expected verifiers.

Existing code has two credential representations. `TrisAuraCredential` and the
Go issuer already model the v2.0 shape. The legacy Dart `VerifiableCredential`
model still expects `issuanceDate` and `expirationDate`; implementation must
move Wallet issuance/storage paths that consume issuer output to
`TrisAuraCredential` before adding passport-specific storage.

Proof encoding remains compatible with the current codebase in the first pass:
issuer credentials may keep the existing Ed25519 proof representation used by
the relay. A later interoperability hardening pass should migrate to
`DataIntegrityProof` with `eddsa-jcs-2022` and multibase `proofValue`.

## Privacy Boundary

The raw passport number is never persisted and never sent to Relay or Issuer.
During a scan, the app holds it only in memory long enough to derive a
device-local unique value:

```text
passportLocalUniqueId =
  HMAC-SHA256(localWalletSecret, "passport:v1|" + nationality + "|" + documentNumber)
```

`localWalletSecret` is generated on first use and stored in platform secure
storage / keystore. `passportLocalUniqueId` is stable only on the local device
and is not shared with the server. It lets the local Wallet detect that the same
passport has already been added on that device without retaining a reversible
passport number.

The local Wallet may store:

- `passportLocalUniqueId`
- `nationality`
- `verifiedAt`
- `assuranceMethod: passport_nfc`
- the encrypted W3C VC payload

The Issuer receives only:

- `holderDid`
- `nationality`
- `verified: true`
- holder/app proof required by the endpoint

The issued VC contains only:

- `humanVerified: true`
- `assuranceLevel: passport_document`
- `assuranceMethod: passport_nfc`
- `nationality`

It must not contain passport number, passport local unique id, legal name, birth
date, raw MRZ, DG1 bytes, DG2 face image, SOD bytes, or provider assertions.

## Architecture

### Passport Reader Boundary

Keep `NfcPassportReader` as the app-facing interface. Replace the current
mock-only behavior with a production-capable reader implementation behind the
same interface. The reader returns `PassportData` with parsed MRZ fields and the
raw chip material needed for future document-authenticity checks, but callers
must only persist privacy-safe derived values.

The first implementation may use the existing `PassportData` model, but its
callers must treat `documentNumber`, raw DG bytes, and SOD bytes as sensitive
ephemeral data.

### Wallet Extension Boundary

Add a local Wallet extension record keyed by credential id or passport local
unique id. This record is local-only metadata associated with the W3C VC payload
and is not part of the VC presented to verifiers.

The extension should be separate from generic `wallet_credentials` metadata so
ordinary credential listing and presentation logic remains simple. The generic
Wallet metadata continues to store credential id, issuer DID, holder DID,
credential type, status, validity, and display name.

### Issuer Boundary

Add a passport issuance endpoint or extend the existing issuer client with a
passport-specific issue method. The payload must not include the passport number
or passport local unique id. The server stores no passport number and no
passport-derived local identifier.

The Issuer may issue a `TrisAuraHumanityCredential` whose subject claims include
`nationality` and `assuranceMethod: passport_nfc`. Duplicate prevention is out
of scope for this phase because the server intentionally does not receive a
cross-device identifier.

### Wallet UI

Add Passport NFC as a method in the existing credential issuance wizard. The
flow is:

1. User opens Wallet and chooses Add credential.
2. User chooses Passport NFC.
3. App checks NFC availability and starts the passport scan.
4. App derives `passportLocalUniqueId` locally.
5. App refuses to continue if the same `passportLocalUniqueId` is already
   associated with an active local passport credential.
6. App requests a passport-backed VC from Issuer with holder DID and
   nationality only.
7. App stores the encrypted VC payload and local passport extension metadata.
8. Wallet shows the credential as Passport Verified Human.

## Data Flow

```text
Wallet UI
  -> NfcPassportReader.scan()
  -> PassportData(documentNumber, nationality, ...)
  -> PassportLocalIdService.derive(nationality, documentNumber)
  -> WalletRepository.findPassportExtension(passportLocalUniqueId)
  -> VcIssuerClient.issuePassportCredential(holderDid, nationality)
  -> TrisAuraCredential.fromJson(vcJson)
  -> SecureCredentialPayloadCodec.seal(vcJson)
  -> WalletRepository.saveCredential(...)
  -> WalletRepository.savePassportExtension(...)
```

Only the first three steps have access to the raw passport number. After
derivation, implementation should avoid passing `documentNumber` into generic
Wallet, repository, issuer, or UI code.

## Error Handling

NFC unavailable:
show a local message that passport NFC is unavailable on this device or
simulator.

Scan cancelled:
return to the Passport NFC panel idle state without creating a local extension
or contacting the Issuer.

Unreadable passport:
show a retryable scan error. Do not persist partial passport data.

Duplicate local passport:
show that this passport is already stored in this Wallet. Do not call Issuer.

Issuer unavailable:
retain no local passport extension unless the VC has been successfully issued
and stored. The user can retry the issuance flow.

Unsupported credential schema:
reject issuer output that is not a W3C VC v2.0 `TrisAuraHumanityCredential`
with expected passport claims.

## Testing

Use TDD for implementation. Required test coverage:

- `PassportLocalIdService` derives the same id for the same nationality and
  document number with the same secret.
- `PassportLocalIdService` derives different ids for different document numbers
  or secrets.
- The derived id test asserts the raw document number does not appear in the
  stored value.
- Wallet repository can save and list passport extension metadata without
  exposing a raw passport number field.
- Passport issuance client sends only holder DID and nationality.
- Passport issuance panel blocks duplicate local passports before contacting the
  Issuer.
- Passport issuance panel stores a W3C VC v2.0 payload via
  `TrisAuraCredential`, not the legacy `VerifiableCredential` parser.
- Existing TW provider and presentation tests keep passing after the shared
  Wallet credential parser is unified on v2.0.

## Non-Goals

- Do not restore passport verification as an onboarding gate.
- Do not store raw passport number, MRZ, DG1, DG2, SOD, or face image.
- Do not send passport number, passport local unique id, MRZ, DG bytes, or SOD
  bytes to Relay or Issuer.
- Do not implement cross-device or server-side duplicate passport prevention in
  this phase.
- Do not make government-grade authenticity claims until chip authentication
  and document security verification are implemented and tested.
