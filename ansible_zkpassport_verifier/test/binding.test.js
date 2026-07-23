import test from "node:test"
import assert from "node:assert/strict"
import { challengeBinding, passportBindingHash } from "../src/binding.js"

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

test("passport identifier never masquerades as a national-ID binding", () => {
  const binding = passportBindingHash("unique-passport")
  assert.deepEqual(Object.keys(binding), ["passport_number_hash"])
  assert.match(
    binding.passport_number_hash,
    /^zkp-passport-v1_[a-f0-9]{64}$/,
  )
})
