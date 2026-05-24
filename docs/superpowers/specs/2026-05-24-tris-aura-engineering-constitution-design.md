# Tris-Aura Engineering Constitution

> Status: Product and engineering base rules
> Date: 2026-05-24
> Scope: Wallet, Issuer, Relay, Forum Host, AppView, federation adapters, and
> future identity or moderation features

## Purpose

This constitution is the highest product and engineering constraint for
Tris-Aura. Feature specs, APIs, data models, storage decisions, moderation
systems, and federation adapters must be evaluated against these rules before
implementation.

Tris-Aura is not a fully anonymous system and is not a real-name social
network. The product goal is self-sovereign identity and user-controlled data
with enough integrity controls to resist spam, coordinated manipulation, and
Sybil attacks. The system may verify that an account represents a unique human,
but it must not learn or expose who that person is unless the user explicitly
chooses to disclose that information.

## Normative Terms

- `MUST` and `MUST NOT` are hard requirements for first-party systems.
- `SHOULD` and `SHOULD NOT` are expected defaults. A deviation requires a
  documented product, security, or legal reason.
- `MAY` means the behavior is allowed but not required.
- `First-party systems` means Tris-Aura-operated Wallet, Issuer, Relay, Forum
  Host, AppView, and first-party federation adapters.
- `External hosts` means third-party federation hosts, relays, app views, or
  community servers that interoperate with Tris-Aura.

## Scope And Compliance

First-party systems MUST fully comply with this constitution.

External hosts are not required to fully comply to interoperate, but their
compliance level MUST be visible when their behavior affects user trust,
distribution, ranking, access control, moderation, or identity verification.

Compliance levels:

- `constitution_compliant`: the host claims and demonstrates compatibility with
  all applicable MUST and MUST NOT rules.
- `compatible`: the host interoperates but does not fully implement or disclose
  every rule.
- `unknown`: the host's behavior has not been evaluated.
- `non_compliant`: the host is known to violate one or more hard rules.

The Wallet and AppView SHOULD let users, communities, and first-party defaults
use compliance level when deciding whether to display, recommend, rank, sync,
or trust content from an external host.

## Conflict Priority

When rules conflict, first-party systems MUST resolve the conflict in this
order:

1. Minimize irreversible identity harm.
2. Preserve data autonomy and explicit consent.
3. Preserve system integrity against spam, coordinated manipulation, and Sybil
   attacks.
4. Preserve community governance with transparency and exit.
5. Minimize censorship and global platform-level rules.

System integrity MAY justify additional verification, rate limits, proof of
work, labels, or temporary restrictions. It MUST NOT justify collecting raw
legal identity, publishing private data, or silently weakening user control.

## Exception Model

First-party systems MUST NOT create silent exceptions to this constitution.

Break-glass exceptions MAY be used only for:

- active security incidents,
- clear legal obligations,
- immediate user safety risks.

Every exception MUST be limited by purpose, time, data scope, and affected
systems. It MUST leave an audit trail. Affected users or communities SHOULD be
notified when notification does not create additional legal or safety risk.

Raw passport numbers, national ID numbers, legal names, birth dates, addresses,
provider assertions, biometric material, and private keys MUST NOT become
available through a default break-glass path. Access to raw legal identity
requires explicit user disclosure or a specific legal process.

## Base Rule 1: Identity Autonomy

Users MUST control their primary identity keys, credentials, and account
portability wherever the product claims self-custody.

First-party systems MUST:

- keep user-held signing keys in platform secure hardware or an explicitly
  reduced-trust mode,
- separate user identity from any single Relay, Issuer, Forum Host, or AppView,
- support identity migration or recovery without making the operator the sole
  authority over the user,
- make identity strength explicit, such as basic passkey, self-custody DID,
  verified human, or external hosted account.

First-party systems MUST NOT:

- require raw legal identity as the default account creation path,
- make a Relay, Issuer, or Forum Host the only authority that can prove the
  user's continued identity,
- silently downgrade from self-custody to hosted custody.

## Base Rule 2: Data Autonomy

User data MUST remain local or user-controlled unless the user chooses a
specific publication, sync, backup, presentation, or federation path.

First-party systems MUST:

- fail closed for private content,
- treat federation and relay sync as explicit distribution paths,
- encrypt private or restricted data before it leaves the user's trusted
  boundary,
- show users which claims or content will be presented to a verifier or
  published externally,
- retain only data needed for the declared purpose.

First-party systems MUST NOT:

- treat unlisted or federated content as private,
- send private content to relays, external hosts, analytics, logs, crash
  reports, or AI services without explicit user intent and a matching privacy
  boundary,
- make backup, sync, or federation opt-out when the data is sensitive.

## Base Rule 3: Minimal-Disclosure Verification

Verification MUST reveal only the minimum claim needed for the decision being
made.

First-party systems MAY verify:

- human verification status,
- uniqueness of a high-assurance personhood binding,
- nationality or jurisdiction when a community explicitly needs it,
- credential validity, expiry, issuer, holder binding, and revocation status.

First-party systems MUST NOT put raw legal identity into public credentials,
relay payloads, forum posts, logs, or external federation payloads by default.
This includes passport number, national ID number, legal name, birth date,
address, phone number, certificate serial, raw MRZ, passport chip data,
provider assertions, and biometric images.

Opaque commitments or nullifiers used for duplicate prevention MUST be keyed,
domain-separated, non-reversible, and stored only where required for duplicate
enforcement. They MUST NOT be included in the issued VC subject or presented to
ordinary verifiers.

## Base Rule 4: Botnet And Coordinated-Manipulation Resistance

The system MUST reduce the influence of cheap accounts, automation, spam, and
coordinated manipulation without requiring real-name public identity.

First-party systems MUST:

- apply stricter limits to lower-trust identities,
- make trust tier upgrades depend on verifiable evidence,
- keep rate limits, suspensions, ranking penalties, and labels reason-coded,
- make temporary restrictions time-bound when possible,
- preserve enough audit information to explain enforcement decisions.

First-party systems SHOULD:

- prefer friction, ranking, rate limits, and community controls before global
  content removal,
- separate spam or manipulation signals from political, social, or cultural
  viewpoint judgments.

First-party systems MUST NOT:

- assign higher trust tiers without verified cryptographic or operational
  evidence,
- use hidden real-name identity as a general anti-abuse shortcut.

## Base Rule 5: Sybil Resistance

High-assurance privileges MAY require one active personhood binding per real
person. The duplicate-prevention mechanism MUST preserve legal-identity privacy.

First-party systems MUST:

- use irreversible personhood commitments, nullifiers, or equivalent
  privacy-preserving duplicate keys for high-assurance paths,
- block a new high-assurance binding when any active commitment already belongs
  to another active credential or account,
- keep low-assurance paths available when legal-identity verification is not
  required by the product surface,
- define what happens when a credential is expired, revoked, suspended, or
  replaced.

First-party systems MUST NOT:

- use raw passport numbers, national ID numbers, legal names, or provider
  subjects as duplicate keys,
- expose personhood commitments in public credentials or normal verifier
  presentations,
- make high-assurance verification mandatory for ordinary private use.

## Base Rule 6: Healthy Community Discussion

The product SHOULD optimize for durable, readable, and accountable discussion,
not maximum engagement at any cost.

First-party systems SHOULD:

- let Forum Hosts define board-level rules, posting permissions, moderation
  policy, and trust requirements,
- support user and community filters,
- make provenance, trust tier, and moderation state visible enough for
  participants to understand the discussion context,
- design ranking and distribution to reduce spam and manipulation.

Forum Host governance MUST be transparent and escapable:

- users SHOULD be able to leave, mute, block, migrate, or choose another host,
- host rules SHOULD be discoverable before posting,
- moderation actions SHOULD be reason-coded and visible to affected users unless
  visibility creates a safety or legal risk.

## Base Rule 7: Minimal Censorship And Minimal Global Rules

System-level rules MUST be limited to security, spam, Sybil resistance,
coordinated manipulation, privacy violations, legal obligations, and high-risk
harm boundaries.

First-party systems MUST:

- keep value judgments and community norms as close to the Forum Host,
  community, or user filter layer as practical,
- distinguish host-level moderation from system-level enforcement,
- preserve user exit and interoperability wherever possible.

First-party systems MUST NOT:

- present a Forum Host's local moderation decision as a universal truth about a
  user or content item,
- silently suppress content across the whole network without a reason-coded
  system-level basis,
- rely on opaque global ranking or moderation rules that cannot be explained at
  least at the category level.

## Review Checklist

Every new feature spec and implementation that touches identity, storage,
sync, verification, federation, moderation, ranking, or community governance
MUST answer these questions:

1. What user-controlled identity or credential is involved?
2. What data leaves the local device, and did the user choose that path?
3. What is the minimum claim needed for the decision?
4. Are raw legal identity fields, provider assertions, private keys, or
   biometric data excluded from credentials, logs, relay payloads, and
   federation payloads?
5. Does the feature change trust tier, ranking, rate limits, access, or
   moderation state? If so, is the reason code explicit?
6. Does the feature create a personhood binding or duplicate-prevention key?
   If so, is it keyed, domain-separated, non-reversible, and hidden from normal
   verifiers?
7. Can users exit, revoke, delete, rotate, migrate, or choose a lower-trust path
   where appropriate?
8. If the feature depends on an external host, is that host's compliance level
   represented or discoverable?

## Current Engineering Implications

- Passport NFC and TW provider verification must remain optional high-assurance
  paths, not account creation requirements.
- `national_id_hash` and `passport_number_hash` may be stored by the Issuer as
  duplicate-prevention keys, but must not appear in the issued VC subject or
  ordinary verifier presentations.
- Email OTP may verify contactability but must not be treated as a personhood
  or Sybil-resistance proof.
- Relay and Forum Host code should treat verified-human status as a trust tier
  input, not as permission to access legal identity.
- Federation adapters must preserve local-first visibility semantics and must
  not distribute private content.
- External Forum Hosts and relays need a compliance-level model before their
  behavior affects first-party ranking, recommendation, or trust decisions.
