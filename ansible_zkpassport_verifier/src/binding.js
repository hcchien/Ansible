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

export function passportBindingHash(uniqueIdentifier) {
  return {
    passport_number_hash: `zkp-passport-v1_${createHash("sha256")
      .update(`zkp-passport-v1\0${uniqueIdentifier}`)
      .digest("hex")}`,
  }
}
