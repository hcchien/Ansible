import test from "node:test"
import assert from "node:assert/strict"
import {
  parseTwPersonBindingProof,
  twPersonBindingCircuit,
} from "../src/tw-person-binding.js"

function field(value) {
  return value.toString(16).padStart(64, "0")
}

test("parses native Swoir proof prefix and eight public inputs", () => {
  const encoded =
    "00000008" +
    Array.from({ length: 9 }, (_, index) => field(index + 1)).join("")
  const parsed = parseTwPersonBindingProof({
    name: "tw_person_binding",
    vkeyHash: twPersonBindingCircuit.vkeyHash,
    index: 5,
    total: 6,
    proof: encoded,
  })

  assert.equal(parsed.publicInputs.length, 8)
  assert.equal(parsed.publicInputs[4], `0x${field(5)}`)
  assert.deepEqual(parsed.proofFields, [field(9)])
})

test("rejects a proof that does not pin the shipped verification key", () => {
  assert.throws(() =>
    parseTwPersonBindingProof({
      name: "tw_person_binding",
      vkeyHash: "0xdeadbeef",
      index: 5,
      total: 6,
      proof: "00000008",
    }),
  )
})
