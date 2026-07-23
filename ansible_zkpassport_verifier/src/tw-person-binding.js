import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { Barretenberg } from "@aztec/bb.js"
import { getProofData } from "@zkpassport/utils"

const CIRCUIT_NAME = "tw_person_binding"
const PUBLIC_INPUT_COUNT = 8
const EXPECTED_VKEY_HASH =
  "0x02c79897440f6ec265c1c79a70f414e642d09fe464a2d1dbd1540cf586940c9e"

const circuit = JSON.parse(
  readFileSync(
    resolve(process.cwd(), "circuits/tw_person_binding.json"),
    "utf8",
  ),
)

if (circuit.vkey_hash !== EXPECTED_VKEY_HASH) {
  throw new Error("TW person-binding verification key mismatch")
}

let barretenberg

function hexBytes(value) {
  const normalized = value.startsWith("0x") ? value.slice(2) : value
  if (!/^(?:[a-fA-F0-9]{2})+$/.test(normalized)) {
    throw new Error("invalid proof hex")
  }
  return Uint8Array.from(Buffer.from(normalized, "hex"))
}

function canonicalField(value) {
  const normalized = value.toLowerCase().replace(/^0x/, "")
  if (!/^[a-f0-9]{64}$/.test(normalized)) {
    throw new Error("invalid public field")
  }
  return `0x${normalized}`
}

export function parseTwPersonBindingProof(proof) {
  if (
    !proof ||
    proof.name !== CIRCUIT_NAME ||
    proof.vkeyHash !== EXPECTED_VKEY_HASH ||
    proof.index !== 5 ||
    proof.total !== 6
  ) {
    throw new Error("invalid TW person-binding proof metadata")
  }
  const encoded = hexBytes(proof.proof)
  if (encoded.length < 4) throw new Error("invalid TW person-binding proof")
  const count = new DataView(
    encoded.buffer,
    encoded.byteOffset,
    encoded.byteLength,
  ).getUint32(0, false)
  if (count !== PUBLIC_INPUT_COUNT) {
    throw new Error("unexpected TW person-binding public input count")
  }
  const parsed = getProofData(proof.proof, PUBLIC_INPUT_COUNT, 4)
  return {
    proofFields: parsed.proof,
    publicInputs: parsed.publicInputs.map(canonicalField),
  }
}

function sameChain(disclosureInputs, bindingInputs) {
  return [0, 2, 3, 5, 6, 7].every(
    (index) =>
      canonicalField(disclosureInputs[index]) === bindingInputs[index],
  )
}

export async function verifyTwPersonBindingProof(envelopeProofs) {
  if (!Array.isArray(envelopeProofs) || envelopeProofs.length !== 6) {
    throw new Error("incomplete passport proof envelope")
  }
  const custom = envelopeProofs.find((proof) => proof?.name === CIRCUIT_NAME)
  const disclosure = envelopeProofs.find(
    (proof) => proof?.name === "disclose_bytes",
  )
  if (!custom || !disclosure) throw new Error("missing passport proof")

  const parsed = parseTwPersonBindingProof(custom)
  const disclosureData = getProofData(
    disclosure.proof,
    PUBLIC_INPUT_COUNT,
  )
  if (!sameChain(disclosureData.publicInputs, parsed.publicInputs)) {
    throw new Error("TW person-binding proof is not chained to disclosure")
  }

  barretenberg ??= await Barretenberg.new()
  const verification = await barretenberg.circuitVerify({
    verificationKey: Uint8Array.from(Buffer.from(circuit.vkey, "base64")),
    publicInputs: parsed.publicInputs.map(hexBytes),
    proof: parsed.proofFields.map(hexBytes),
    settings: {
      ipaAccumulation: false,
      oracleHashType: "poseidon2",
      disableZk: false,
      optimizedSolidityVerifier: false,
    },
  })
  if (!verification.verified) {
    throw new Error("invalid TW person-binding proof")
  }
  return parsed.publicInputs[4]
}

export const twPersonBindingCircuit = {
  name: CIRCUIT_NAME,
  publicInputCount: PUBLIC_INPUT_COUNT,
  vkeyHash: EXPECTED_VKEY_HASH,
}
