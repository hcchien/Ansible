# MozFest 2026 Submission — Ansible / Tris-Aura

**Track:** Wilding Systems
**Format:** Talk (20–30 min)
**Deadline:** 2026-05-24
**Form:** https://appv2.sessionboard.com/submit/mozfest-2026/84f42512-cfc7-421a-9ded-00bfb65cf4d4

---

## Session Title

**Wilding the Forum: Federation as Output, Built from Taiwan** (58 chars)

(Backup: *"Federation as Output: A Local-First, Polyprotocol Forum"* — 55 chars)

---

## Short Summary / Tagline (1–2 sentences, ~280 chars)

Built from Taiwan's disinformation front line, Ansible is a pseudonymous forum that keeps your data on your device, treats federation as a swappable output instead of a cage, and replaces passwords and passports with hardware-bound, progressive trust.

(Tighter alt, ~190 chars: "A pseudonymous forum from Taiwan's disinformation front line — data lives on your device, federation is a swappable output, identity is hardware-bound and progressive.")

---

## Session Description (long-form, ~300–500 words)

We've spent a decade watching "open" platforms recentralize: federated networks where three instances host most users, "decentralized" identity that quietly depends on one directory, "self-sovereign" wallets that lose your keys for you. Each well-meaning protocol becomes a new monoculture — and communities lose their history when those monocultures fail, are blocked, or capitulate.

I build from Taiwan, which has sat on the front line of state-backed disinformation, coordinated 網軍 (cyber-army) operations, and platform-level coercion for more than a decade. That vantage point changes what counts as "best practice." The people most targeted — journalists, civic-tech organizers, diaspora communities, queer and dissident voices — often cannot or will not surrender legal identity to participate in public discourse. The platforms they rely on can be blocked, captured, or coerced overnight. Account takeover and credential farming are routine, not edge cases. These are not future concerns; they are Tuesday.

Ansible (codename Tris-Aura) is a working response: a pseudonymous, Sybil-resistant peer-to-peer discussion network built on three commitments that are unusual together.

**Your data lives on your device, not in a platform.** The canonical record — posts, follows, reputation, history — is stored locally on the user's phone or laptop. The network distributes that record; it does not own it. If a platform is blocked, captured, or coerced, the community's discussion survives on the devices of the people who wrote it.

**Federation is an output you can swap, not a cage you live in.** Public content can be projected into AT Protocol, Nostr, or ActivityPub independently, in parallel, and revocably. No single protocol owns the user. If one ecosystem collapses or capitulates, the local record re-projects elsewhere — no migration, no lost history.

**Identity is progressive, not binary.** Account creation uses Passkeys: keys that live in the device's secure hardware, never written to disk, biometric-gated on every signing operation. Trust then layers up — a verified DNS-based handle, an optional out-of-band human-verification step — instead of demanding a binary identity gate. We deliberately rejected an earlier design that gated participation behind a zero-knowledge proof over passport data: accessibility and progressive trust beat a "real human" wall, especially for the users who most need a pseudonymous voice.

The talk shares what we built, what we tore out, and what we still don't know how to solve. It also names the centralization that remains in our own system — every "decentralized" project has some — and the principles that guide what we migrate away from first.

---

## Why did you choose this track? How does your session align with the track description?

Wilding Systems is described as a track for systematic conversations on open source, governance models, platform accountability, and moving away from centres of control toward more accountable alternatives. Ansible sits squarely in that conversation — not as a thought experiment, but as a working forum that has had to make every one of those choices in production.

On open source: the entire stack — cryptography core, relay, and client — is MIT-licensed and developed in the open. On governance: forum hosts own their boards, members, and moderation policies; the platform layer cannot revoke a community's existence. On platform accountability: by treating federation as a swappable output rather than a cage, the system inverts the usual power asymmetry — if a platform misbehaves, the community walks, and the canonical record on user devices walks with them. On moving away from centres of control: I am explicit about the centralization that remains in our own system, and publish the migration path away from each piece of it.

The Taiwan vantage point is also why this belongs in Wilding Systems rather than Developers Wilding. The questions the talk raises — who gets a pseudonymous voice, who decides which communities exist, who can pull the plug — are governance questions, not implementation questions. The implementation only matters because it makes a particular set of governance choices physically possible.

---

## Why this matters for MozFest / Wilding (Why this is important)

Wilding Systems asks how we move away from centres of control toward accountable alternatives. The dominant pattern of "decentralization" is still centralization with extra steps — a federated network where three instances host 90% of users, or a self-sovereign wallet that depends on one custodian's recovery service.

Ansible is a concrete answer to that pattern: a local-first canonical model the user actually owns, federation treated as a *replaceable output*, and identity rooted in hardware the user already carries. None of these ideas is new on its own; the contribution is showing they compose into a working forum that doesn't require a passport, a password, or a platform.

For builders in the Wilding Systems track, the talk offers a vocabulary and a working reference for "polyprotocol by construction" — what it costs, what it earns, and which parts you can copy. It also brings a perspective that is under-represented in Western FOSS conversations: design constraints from Taiwan, a society where coordinated disinformation and platform-level coercion are not edge cases but daily threat models. Decisions that look "paranoid" from a Berlin or San Francisco vantage point are baselines here.

---

## Why are you bringing this to MozFest? Why is this topic important to you and the community you hope to reach?

I am bringing this to MozFest because MozFest is one of the few global gatherings where the question is not "can we ship this faster" but "should we be shipping this at all, and on whose terms." That is the conversation Ansible has had to have with itself, in production, for two years. I want it stress-tested by the people who think hardest about internet health.

The topic matters to me personally because I live in Taiwan. The threats this system is designed against are not slides — they are the daily reality for journalists, civic-tech organizers, queer and dissident communities, and ordinary people who hold opinions in public. Designing for them is not an exercise in protocol elegance; it is a question of who gets a voice and who does not.

It matters to the community I hope to reach because there are two audiences in that room at the same time. The first is builders of decentralized alternatives who keep watching their projects re-centralize despite their best intentions, and who would benefit from a working pattern that breaks the cycle. The second is advocates, journalists, and organizers who do not write code but who carry the consequences of platform decisions every day — and who deserve a voice in the room where those decisions get made.

MozFest is the rare room where both audiences are present at once. I want the talk to be a contribution to the conversation that already happens there — and a reason for the next person from Taiwan, or from any front-line context, to bring their own work too.

---

## How will your session demonstrate proof points or examples of community-led technology?

Three concrete proof points, in order of how prominently the talk uses them.

First, the architectural pivot itself. Ansible's V1.x design required an ePassport-based zero-knowledge proof for participation — elegant on paper, but it would have excluded exactly the communities most in need of a pseudonymous voice: people without passports, people whose governments would link a passport to an account, people who simply refuse to surrender legal identity to speak in public. We tore that out and replaced it with Passkeys plus progressive, layered trust. That decision came from listening to the people Ansible is for. The talk walks through the conversations that produced it.

Second, forum host sovereignty. In Ansible, communities own their forums — not as a marketing claim, but as a data model decision. Boards, threads, members, moderation policies, and permissions belong to a forum host identity that the platform layer cannot revoke. A community can run its own host, fork to another, or take its content with it. The platform does not get to delete a community out of existence. The talk shows how this is implemented and what it costs.

Third, the protocol stack itself. Ansible is built on AT Protocol, Nostr, and ActivityPub — three community-led standards that exist precisely because the formal standards process was not delivering what communities needed. Treating federation as a swappable output across all three is a downstream proof point of what becomes possible when multiple community-led protocol traditions are treated as peers rather than competitors.

There is a fourth, indirect proof point worth naming: Ansible is built from Taiwan, downstream of one of the most active civic-tech traditions in the world — g0v's open hackathons, vTaiwan's participatory governance, the "rough consensus and running code" lineage that has shaped how technology decisions get made here for over a decade. The talk credits that lineage explicitly.

---

## What engagement opportunities does your session provide for participants after the festival?

Several paths, scaled to how participants want to engage.

For people who want to read more: every architectural decision discussed in the talk is documented in public design docs in the project repository — the V1→V2 pivot rationale, the polyprotocol federation strategy, the security policy that gates launch. These are not marketing pages; they are the working documents that produced the system. The talk closes with direct links to each.

For people who want to try it: the code is MIT-licensed and the project is in active alpha. Attendees can run the client locally, stand up their own relay, or self-host a forum to test the community-sovereignty model in practice. I will publish a short "first hour" path before the festival.

For people who want to shape the system: the design decisions still ahead — the migration off the Genesis Relay, the threat model for human-verification attestation, the UX of cross-protocol identity — benefit from non-engineer input. I will publish a list of "questions I would like you to push back on" before MozFest and collect responses in a public thread open for at least three months after.

For people who want to contribute their own context: the talk closes with one transferable ask — which "best practices" from your context survive contact with adversarial conditions, and which do not? I will publish that as a public, CC-BY collection — **"Adversarial Defaults: A Cross-Context Field Report"** — hosted on a dedicated GitHub repository. Contributors fill in a short structured template (context and threat model, one practice that survived, one that did not, what replaced it, one sentence to builders elsewhere). I seed it with my Taiwan piece plus two commissioned reports from adjacent contexts before the festival, accept community PRs for six months, and close with a synthesis post that names patterns across submissions. Contributors are credited with a stable URL. The collection is the concrete artifact this MozFest session leaves behind — usable by future MozFest tracks, by journalists, and by anyone building infrastructure under threat.

I also welcome being approached in person at the festival; I find hallway conversations more useful than most formal sessions.

---

## Audience (Who is this for?)

- Platform-accountability advocates and policy researchers evaluating decentralized alternatives
- Civic-tech builders, journalists, and community organizers working in high-risk information environments
- Designers and architects of federated, decentralized, or local-first systems
- Identity and trust-and-safety practitioners interested in alternatives to identity-gated participation
- Anyone tired of "decentralized" projects that quietly recentralize

Assumed background: interest in how online discourse infrastructure is built and governed. No specific technical expertise required.

---

## Key Learning Outcomes / Takeaways

1. **A field report from Taiwan's disinformation front line** — which "best practices" from Western FOSS contexts survive contact with coordinated 網軍 / state-actor adversaries, and which defaults must change before they ship to high-risk users.
2. **A pattern for treating federation as a swappable output** — why monoprotocol "decentralization" keeps re-centralizing, and what it costs to break that cycle.
3. **A practical case for progressive trust over identity-gated trust** — what you give up, what you gain, and how to build Sybil resistance without demanding a passport.
4. **An honest map of the centralization that remains in our own system** — and the principles we use to decide what to migrate first.

---

## Your relationship to the topic / Speaker Bio

I am the founder and lead architect of Ansible / Tris-Aura. I made the architectural pivot from a passport-gated zero-knowledge-proof identity model to Passkeys with layered, progressive trust — and the strategic pivot from picking a single federation protocol to treating AT Protocol, Nostr, and ActivityPub as interchangeable output adapters. I work across the cryptography, server, and client layers of the system.

I build from Taiwan, which means the threat model is not theoretical: coordinated 網軍 campaigns, platform-level coercion, and state-backed disinformation are part of the daily context that shapes the system's defaults. That perspective informs why Ansible privileges pseudonymous-but-Sybil-resistant participation over identity-gated trust, and why federation is treated as a replaceable output rather than a single point of capture.

---

## Speaker Name / Contact

- Name: HC Chien (錢小姚)  *(← please correct if needed)*
- Email: hcchien@gmail.com
- Pronouns: *(please fill in)*
- Organization / Affiliation: Independent — Ansible / Tris-Aura
- Location / Time zone: *(please fill in — Taipei UTC+8?)*
- Social / Web: *(GitHub / website / fediverse handle — please fill in)*

---

## Background / identity / lived experience — what perspective do you add?

I bring an unusual cross-section of perspectives into this conversation, all rooted in Taiwan.

I started as a developer and crossed into media. I founded **READr**, Taiwan's first pure data-journalism outlet, and later founded **Mesh**, a federated media-community platform that united more than thirty Taiwanese news organizations using blockchain infrastructure for cross-publisher coordination. That is more than a decade of direct, operational experience inside the information ecosystem — not as a researcher writing about it, but as someone making editorial, identity, and platform decisions under the same disinformation pressure the talk is about. The fact that I now build a federated, pseudonymous-but-Sybil-resistant forum is downstream of watching what happens to journalism when platform power is unchecked.

I have also been a long-term contributor to g0v.tw — Taiwan's civic-tech community and one of the most active and explicitly community-led civic-tech traditions in the world — and a long-term participant in the Taiwanese open-source community. I co-organized OSDC.tw, the largest open-source developers' conference Taiwan has hosted. These are not credentials I list to signal authority; they are why I am credible when I claim that community legitimacy and code legitimacy are the same question, and that "rough consensus and running code" is a working ethic rather than a slogan.

I build independently — not under a corporate sponsor — on infrastructure shaped by a society that has been on the front line of state-backed disinformation and platform-level coercion for over a decade. That vantage point is not common in the rooms where federation protocols, identity standards, and platform-accountability frameworks get debated, which are still disproportionately Western European and North American. The constraints that shape decisions here — anonymous participation as a basic safety requirement rather than a privacy preference, federation as an exit option rather than an interop nicety, the cost of platform capture measured in real arrests rather than thought experiments — change what counts as a sensible default. That combination — developer, media founder, civic-tech contributor, open-source community organizer, Taiwanese — is what I want to bring into the room.

> Note: other identity dimensions (pronouns, gender, sexuality, disability, class, neurodiversity, age) deliberately left out — extend if comfortable.

---

## Language support needed (English is not first language)

English is not my first language, but I work in it daily and can deliver a prepared talk and follow most conference discussion comfortably. Where I would appreciate light support is during Q&A: when questions come at speed or from accents I don't encounter often, I would value a moderator who can re-state or summarize the question before I answer. I do not need formal interpretation, captioning, or written-only Q&A. Mandarin Chinese is my first language, and I am also happy to take questions in Mandarin from any attendees who prefer it.

---

## Logistical Q&A (likely sessionboard fields)

- **First time submitting to MozFest?** *(please confirm Y/N)*
- **Can you attend in person in Barcelona, Oct 28–30, 2026?** *(please confirm — in-person / remote / either)*
- **Do you need financial support to attend?** *(please confirm Y/N)*
- **Are you submitting on behalf of an organization?** No — independent project
- **Co-presenters?** *(please confirm — solo or co-speakers)*
- **Languages you can present in?** English; Mandarin Chinese (中文)
- **Code of Conduct agreement:** Yes, I agree to the MozFest Participation Guidelines

---

## Tags / Keywords (if requested)

decentralization, federation, local-first, AT Protocol, Nostr, ActivityPub, Passkeys, WebAuthn, did:plc, Sybil resistance, pseudonymity, P2P, MST, Merkle Search Tree, polyprotocol, hardware-bound keys, Secure Enclave, open source, community-led infrastructure, disinformation, Taiwan, civic tech, threat modeling
