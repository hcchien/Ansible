/// ansible_vc — Verifiable Credentials for Tris-Aura
///
/// V2.0 (active): W3C VC / VP + Passkeys + AT Protocol Lexicon signing.
/// V1.1 (superseded): NFC passport + ZKP Groth16, kept for reference.

library ansible_vc;

// V2.0 — Tris-Aura humanity VC verification / presentation
export 'src/tris_aura_credential.dart';
export 'src/vc_verifier.dart';
export 'src/vp_builder.dart';

// V2.0 — generic W3C VC / VP wallet flow
export 'src/verifiable_credential.dart';

// V2.0 — AT Protocol Lexicon
export 'src/lexicon_record.dart';
export 'src/lexicon_signer.dart';

// V1.1 — NFC + ZKP (superseded; passport/zkp still used by the credential wizard)
export 'src/passport_data.dart';
export 'src/nfc_passport_reader.dart';
export 'src/zkp_proof.dart';
