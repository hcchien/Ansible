# Store Listing — Privacy Policy URLs & Data Disclosure Answers

Effective policy date: **2026-07-07**. Privacy contact: **privacy@reviz.tw**.

The legal pages are served by the web frontend (`ansible_distribution_frontend`,
content in `src/legal_pages.mjs`) as real path-based, server-rendered pages —
they work without JavaScript, which is what store reviewers require. Each page
is bilingual (zh-Hant first, English under the `#en` anchor).

## URLs to paste into the consoles

| Purpose | URL |
| --- | --- |
| Privacy policy (App Store Connect + Play Console) | `https://forum.elix.cool/privacy` |
| Support URL (App Store Connect) | `https://forum.elix.cool/support` |
| Terms of service | `https://forum.elix.cool/terms` |
| About page | `https://forum.elix.cool/about` |
| Account deletion (Play Console "Account deletion" URL, required) | `https://forum.elix.cool/account-deletion` |

- **App Store Connect** → App Information → Privacy Policy URL:
  `https://forum.elix.cool/privacy`
- **App Store Connect** → App Information → Support URL:
  `https://forum.elix.cool/support`
- **Play Console** → App content → Privacy policy:
  `https://forum.elix.cool/privacy`
- **Play Console** → App content → Data safety → Account deletion:
  in-app deletion **supported** (Settings → Sign out this device → Clear local
  identity), web resource: `https://forum.elix.cool/account-deletion`

The in-app About screen (`ansible_node/app/lib/screens/about_screen.dart`)
links to the same four pages; the origin is the compile-time dart-define
`ANSIBLE_FORUM_WEB_BASE_URL` (default `https://forum.elix.cool`).

## Ground-truth data flows (what the answers below derive from)

- Self-sovereign DID identity; Ed25519 private keys on-device only, excluded
  from cloud backup. No analytics/tracking/ads/third-party SDKs. Aggregate-only
  operational metrics; no per-user telemetry. IPs not persisted. No location.
- Relay stores: public DID + handle, signed public posts/ops (append-only log),
  moderation records, device push tokens (content-free sync hints).
- Issuer: email + OTP in memory for ~minutes, then discarded; retains only a
  keyed, irreversible hashed commitment for duplicate (Sybil) prevention.
  Passport NFC / TW MobileMoica data processed transiently, never stored.
  VCs live in the user's on-device wallet; revocation supported.
- AppView: projection of already-public relay content only.
- Deletion: in-app local-identity clearing; author deletes propagate to the
  AppView; relay op log is append-only (content removed from serving, signed
  log retained); full deletion requests via privacy@reviz.tw.

## App Store Connect — App Privacy questionnaire

**Data Used to Track You: NONE.** (No tracking, no ads, no third-party SDKs.)

**Data Linked to You:**

| Data type | Answer | Purpose | Notes |
| --- | --- | --- | --- |
| Identifiers → User ID | Collected | App Functionality | The public DID + handle — this *is* the account. |
| User Content → Other User-Generated Content | Collected | App Functionality | Signed public posts/ops stored on the relay. |
| Contact Info → Email Address | Collected | App Functionality | Transmitted to the issuer during identity verification only; held in memory ~minutes, then discarded. Only an irreversible keyed hash is retained for duplicate prevention — and that hash is stored alongside the holder DID (`personhood_bindings.holder_did` + `commitment`, see `ansible_issuer/go/internal/pgstore/pgstore.go`), so it is linked to the account identity. |

**Data Not Linked to You:**

| Data type | Answer | Purpose | Notes |
| --- | --- | --- | --- |
| Identifiers → Device ID | Collected | App Functionality | Push token, used solely as a content-free sync hint. |

**Not declared (with rationale — verify before submitting):**

- Government ID (passport NFC / MobileMoica): processed ephemerally during
  verification, never stored anywhere. Disclosed in the privacy policy.
- Location, contacts, browsing history, diagnostics, usage data: not collected.
- Precise reviewer note if asked: operational metrics are aggregate counters
  with no per-user dimension.

**Resolved 2026-07-07:** the issuer *does* store the email hashed commitment
keyed to the DID (`personhood_bindings` table: `holder_did` + `commitment`),
so Email Address is declared under "Data Linked to You" above.

iOS permission usage strings already shipped: NFC (ePassport reading), Camera
(QR scanning), Local Network.

## Play Console — Data safety form

- Does your app collect or share any of the required user data types? **Yes**
- Is all of the user data collected by your app encrypted in transit? **Yes** (HTTPS)
- Do you provide a way for users to request that their data is deleted? **Yes**
  (in-app + `https://forum.elix.cool/account-deletion`)

| Data type | Collected | Shared | Ephemeral | Required | Purpose |
| --- | --- | --- | --- | --- | --- |
| Personal info → Email address | Yes | No | No (raw email is memory-only ~minutes, but an irreversible keyed hash linked to the account DID is retained for duplicate prevention — safer to not claim ephemeral) | Optional (only for identity verification) | Account management, Fraud prevention/security |
| Personal info → User IDs | Yes | No | No | Required | App functionality (public DID/handle) |
| Messages → Other in-app messages / User-generated content → Posts | Yes | No | No | Optional | App functionality (public posts, user-initiated) |
| Device or other IDs | Yes | No | No | Optional | App functionality (push token, content-free sync hints) |

Everything else (location, contacts, financial info, health, photos, audio,
files, calendar, browsing history, installed apps, diagnostics/analytics):
**Not collected.**

- Data shared with third parties: **None.** (Federation distribution of public
  posts is user-initiated publishing, not "sharing" in the Play sense; note it
  in the free-text description if a reviewer asks.)
- Android permissions shipped: `CAMERA` (QR scanning).

**Play free-text deletion description (suggested):** "Users can delete their
local identity in-app (Settings → Sign out this device → Clear local identity)
and delete individual posts, which propagates to reading surfaces. Public posts
are part of an append-only signed log: deleted content stops being served, and
the signed log entries are retained for record integrity, as disclosed in the
privacy policy. Full deletion requests: privacy@reviz.tw."

## Honesty guardrails (do not soften these in console free-text)

1. Relay deletion removes content from all serving surfaces but the append-only
   signed log is retained — the policy says this explicitly; keep console
   answers consistent with it.
2. Do not claim "no data collected": DID/handle, public posts, and push tokens
   are server-side data.
3. Do not declare analytics/diagnostics as collected — there are none.
