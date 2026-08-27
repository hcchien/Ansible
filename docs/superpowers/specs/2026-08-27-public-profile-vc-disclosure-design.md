# Public Profile VC Disclosure Design

## Goal

Let a person choose, independently for each active Wallet credential, whether
that credential contributes a minimal verified badge to their public profile.
The credential itself remains in the Wallet and is never copied into the
public Relay operation stream or AppView profile table.

## User Experience

- Every active Wallet credential shows a `Show on profile` switch.
- The default is off. Expired, revoked, suspended, deleted, or payload-missing
  credentials cannot be enabled.
- Enabling opens a preview that names the exact public result and states that
  the complete VC, credential identifier, holder identifier, and prohibited
  identity fields are not published.
- Confirming saves a device-local preference and routes to the explicit Sync
  surface. The existing sync user-presence ceremony is performed once for the
  whole sync batch; all selected VC presentations and the signed profile
  operation reuse that same hardware-authentication context. There is no
  Face ID prompt per VC.
- Disabling saves the preference and routes through the same signed sync flow.
  The next profile operation omits that credential type, which removes the
  badge from AppView while retaining the local VC.
- The public profile shows only Relay-verified badge summaries. It never trusts
  a label or claim sent directly by the holder.

## Data Flow

1. The Wallet stores selected credential IDs in secure local storage.
2. During an explicit authenticated sync, the App creates a verifier-bound VP
   for every selected, active credential and sends it to the selected Relay.
3. The Relay verifies holder proof, issuer proof, holder binding, type, and
   expiry. It derives a fixed allow-listed public summary and stores no raw
   legal identity fields in the public-profile disclosure row.
4. The signed profile op contains only the selected credential types. When the
   Relay serves that op, it intersects the signed selection with its verified
   disclosure rows and attaches the sanitized results.
5. AppView projects only those sanitized results into the public profile.

Supported summaries:

- `TrisAuraHumanityCredential` -> verified-human assurance label only.
- `AgeOver18Credential` -> `18+` only when the signed claim is true.
- `NationalityCredential` -> ISO nationality value only when
  `nationalityVerified` is true.
- `TaiwanCitizenshipCredential` -> Taiwan citizenship only when
  `citizenshipVerified` is true.
- `EmailCredential` is deliberately not eligible for public-profile display.

## Failure And Revocation Semantics

- A failed VP presentation prevents that badge from appearing; it does not
  fall back to a self-asserted label.
- AppView receives an empty badge list when all switches are disabled.
- Expired credentials are excluded locally and by the Relay.
- A later issuer/status failure must remove the Relay disclosure row before it
  can be projected again. Until online status checking is available for every
  issuer, expiry and a new signed profile update are the implemented automatic
  invalidation boundaries.

## Constitution Review

1. The user-controlled objects are Wallet VCs and the holder's self-custody DID.
2. A complete VC leaves the device only as an explicit verifier presentation to
   the chosen Relay after preview and user presence. It never enters public ops.
3. The minimum public claims are an allow-listed badge type and, only where
   necessary, a boolean or ISO nationality value.
4. Raw legal identity, provider assertions, private keys, biometric data,
   credential IDs, document numbers, birth dates, addresses, and personhood
   commitments are excluded from Relay public payloads, AppView, and federation.
5. The existing verified-human badge may describe trust tier; nationality and
   age badges do not change ranking, access, moderation, or rate limits.
6. No new personhood binding or duplicate-prevention key is created or exposed.
7. Every badge is opt-in and removable. Removing it preserves the local VC.
8. The verifying Relay remains visible as the selected sync target; AppView
   projects the Relay-verified summary rather than becoming a credential issuer.

This design complies with the Tris-Aura Engineering Constitution's identity
autonomy, data autonomy, and minimal-disclosure requirements. It does not claim
complete revocation compliance for issuers that lack online status resolution;
that remains an explicit known limitation.
