import { createHash } from "node:crypto"

export function challengeBinding(input) {
  return createHash("sha256")
    .update(
      JSON.stringify({
        challenge_id: input.challenge_id,
        challenge_nonce: input.challenge_nonce,
        did: input.did,
        issuer: input.challenge_issuer,
        scope: input.challenge_scope,
      }),
    )
    .digest("hex")
}

export function personhoodHashes(uniqueIdentifier) {
  const derive = (label) =>
    `${label}_${createHash("sha256")
      .update(`${label}\0${uniqueIdentifier}`)
      .digest("hex")}`
  return {
    national_id_hash: derive("zkp-national-v1"),
    passport_number_hash: derive("zkp-passport-v1"),
  }
}
