import test from "node:test"
import assert from "node:assert/strict"
import { challengeBinding, personhoodHashes } from "../src/binding.js"

const challenge = {
  challenge_id: "challenge",
  challenge_nonce: "nonce",
  did: "did:plc:abcdefghijklmnop",
  challenge_issuer: "https://issuer.elix.cool",
  challenge_scope: "elix-passport-personhood-v1",
}

test("challenge binding is deterministic and nonce-bound", () => {
  const first = challengeBinding(challenge)
  assert.match(first, /^[a-f0-9]{64}$/)
  assert.notEqual(
    first,
    challengeBinding({ ...challenge, challenge_nonce: "different" }),
  )
})

test("personhood outputs are domain-separated", () => {
  const hashes = personhoodHashes("unique-passport")
  assert.notEqual(hashes.national_id_hash, hashes.passport_number_hash)
  assert.match(hashes.national_id_hash, /^zkp-national-v1_[a-f0-9]{64}$/)
})
