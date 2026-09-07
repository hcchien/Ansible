# Relay recovery and own following/followers

## Constitution Review

Read engineering constitution and compliance review. Default Relay selection is explicit in the form and only saved on user confirmation; deleting the last Relay does not silently restart distribution. Local-only follows remain local. Existing accepted/pending/rejected relationship semantics and target approval are preserved. No new trust tier, identity disclosure, or public relationship publication is implied by viewing a list.

## Implementation and verification

- Relay form: production preset plus custom URL, visible empty-value fallback, safe HTTP(S) validation and keyboard/compact-layout support. Empty node list offers one-click form recovery; deletion supports undo. Switching origins drops obsolete auth/sync metadata and rechecks host declaration.
- App own-profile/settings links to following/followers with accepted counts, pending sections, name/handle/DID search, empty/error/retry states, and existing profile actions. Local DB is the source for private/local follow state. Implemented for the shared mobile/desktop App; Web is outside this change.
- Tests cover explicit save/cancel, blank/default/custom inputs, final Relay deletion/recovery, accepted/pending/local-only/board/deleted relationships, navigation and mobile layout.

## Validation

- Targeted Flutter analysis: no issues.
- Five relevant test files: 26 tests passed, including existing profile/follow-button regressions.
- Additional rendering check uses the app theme at 390px and 1200px; compact behavior also tested at 320px.
- Release target: prod and TestFlight 1.0.10 (2026090702), authorized by the user. Upload and Apple processing are verified separately.
