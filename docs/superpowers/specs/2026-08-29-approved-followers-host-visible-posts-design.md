# Approved Followers And Host-Visible Posts

> Status: implementation specification
> Date: 2026-08-29
> Scope: native Elix follows, Relay ops, local follow state, protected personal posts, and App UI

## Goal

Add two related behaviors without introducing identity-credential gating:

1. following another Elix user creates a request which that user can accept or reject;
2. an author may publish a murmur or note for approved followers only.

Approval creates an author-issued `FollowGrantCredential`. This is a social
relationship credential, not evidence of legal identity, personhood, reputation,
or possession of a third-party VC.

## Constitution Review

- The request is signed by the follower DID. The grant is signed by the target
  author DID and is holder-bound to the follower DID.
- The credential contains only the issuer DID, holder DID, relationship,
  request identifier, policy version, timestamps, and status reference. It must
  not contain Wallet credentials, legal identity, personhood commitments, or
  profile claims.
- Followers-only content uses the existing `host_visible` trust model: the
  author's selected first-party Host stores plaintext and can read it. The UI
  must disclose this. It must never call this mode end-to-end encrypted.
- Host-visible content is excluded from public delta, AppView, search,
  snapshots, previews, publication intents, Nostr, and ActivityPub.
- A reader must present a short-lived, DID-bound sync capability and have an
  active author-issued grant. Missing, rejected, revoked, expired, malformed,
  or unverifiable state fails closed.
- Revocation stops future fetches. It cannot remove content already downloaded
  or seen, and the UI must not imply otherwise.
- No trust tier, ranking, moderation state, or personhood binding changes.
- Unsupported external hosts and federation rails receive no protected
  content. There is no public fallback.

This is constitution-compliant as a clearly labelled host-visible mode. The
separate `end_to_end_encrypted` mode remains behind its cryptographic-review
gate.

## Protocol

### Follow request

The follower publishes a signed `follow` insert op keyed by the target DID:

```json
{
  "targetDid": "did:elix:author",
  "state": "requested",
  "visibility": "federated",
  "createdAt": "..."
}
```

The op author is the follower DID. It creates a pending outbound edge for the
follower and a pending inbound edge for the target.

### Follow grant credential

Acceptance publishes a signed `follow_grant` insert op. The op author and VC
issuer are the followed user. The holder is the requesting follower.

```json
{
  "requestOpId": "...",
  "followerDid": "did:elix:follower",
  "targetDid": "did:elix:author",
  "credential": {
    "type": ["VerifiableCredential", "FollowGrantCredential"],
    "issuer": "did:elix:author",
    "credentialSubject": {
      "id": "did:elix:follower",
      "relationship": "approved_follower",
      "targetDid": "did:elix:author"
    },
    "issuanceDate": "..."
  }
}
```

The containing op signature is the credential proof. Relay and clients verify
that the request exists, targets the issuer, and was authored by the holder.
The AppView follow graph materializes only a matching active request plus grant.

Rejection or later revocation is a `follow_grant` delete signed by the target.
The payload retains only the request/follower/target identifiers and a reason
code (`rejected` or `revoked`).

### Followers-only content

`ContentVisibility.followers` serializes as `followers`. Relay accepts it only
for standalone `murmur` and `note` ops. These rows remain in the Host op log but
are never returned by public delta or snapshot and are never projected by
AppView.

An approved reader fetches:

`GET /api/v1/followers/:author_did/ops/delta?reader=<did>&cursor=&limit=`

The endpoint always requires a valid short-lived sync capability whose subject
equals `reader`, plus an active matching `FollowGrantCredential`. Responses are
cursor-based and contain only the selected author's `followers` content.

## Product behavior

- Profile button states: Follow, Requested, Following, Rejected.
- The target receives a local notification labelled “requested to follow you”.
- Opening the requester profile exposes Accept and Reject actions.
- Accept immediately creates the grant and changes both users to Following
  after sync. Reject removes the request from the pending list.
- Composer audience choices are: only me, approved followers, unlisted, public.
- Approved-followers copy states that Elix Host can process/read the post and
  that removing a follower cannot erase copies already seen or downloaded.
- A followers-only post never exposes a federation selector.

## Non-goals

- No third-party VC requirement for following.
- No automatic trust-tier or reputation change.
- No E2EE claim or encryption-key distribution.
- No followers-only ActivityPub or Nostr delivery.
- No retroactive removal from an already-authorized device.
