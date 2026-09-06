# Discovery and public profile UX

## Scope

Improve Flutter phone and desktop entry points and public-profile guidance.
Discovery gets a labelled phone navigation destination and a desktop sidebar
entry. Phone navigation uses Timeline / Discover / compose / Notifications / Me.
Discover contains People / Boards / Posts; Boards links to subscribed boards.
Desktop retains its board sidebar.
The phone Discovery destination keeps navigation available.

Use a shared status card in Discover and settings. Check the exact DID's public
AppView profile, independently of follow recommendations (which exclude self).
Distinguish checking, not indexed, indexed, local changes and lookup failure.
Never equate a local contact, successful save or sync completion with indexing.

The editor previews the public display name and handle and clearly labels its
save action as continuing to publication. An unchecked consent field and a
cancellable confirmation precede writes, describing the next authorized sync
and its other pending content. The People invitation follows results and can
be dismissed for the current visit. The existing authorized sync path
remains responsible for signing/uploading; a focused explanation and public
status check accompany it. Users may skip onboarding. No new auto-publication,
credentials disclosure, withdrawal guarantee or production migration is added.

## Constitution Review

Read the engineering constitution and current compliance review before editing.
Only the current DID's already-public projection is read. Public fields remain
explicit in the editor; keys, raw identity, private content and Wallet claims are
not added. No trust, ranking, verification or custody rules change. Existing
publication/signature authorization remains in place. External-host policy and
hardware-custody gaps documented in the compliance review remain out of scope;
this does not claim repository-wide compliance. DID migration deduplication and
profile withdrawal require separate backend work, not misleading UI promises.

## Validation

Check narrow-phone navigation and destination switching; exact-DID lookup,
404 versus network error, indexed versus unsent local edits; onboarding skip,
public preview, canonical handle protection and post-save guidance. Run focused
Flutter tests and analyze touched files. Build iOS from the scoped release
commit using production defines and App Store Connect distribution signing.
Verify upload, Apple processing, and internal tester assignment separately.

Design reference: Claude Design Elix project, N01/N02, reviewed 2026-09-06.
This release implements the Flutter flow; Web prototype changes remain a
separate implementation. Existing handle registration and sync policy remain
unchanged; this consent covers changes made through this profile editor.
