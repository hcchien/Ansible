import { ZKPassport } from "@zkpassport/sdk"
import { challengeBinding, personhoodHashes } from "./binding.js"

function alpha3(value) {
  if (typeof value !== "string") return undefined
  const normalized = value.trim().toUpperCase()
  return /^[A-Z]{3}$/.test(normalized) ? normalized : undefined
}

export async function verifyPassportRequest(input) {
  const envelope = input.proof_envelope
  if (
    !envelope ||
    !Array.isArray(envelope.proofs) ||
    envelope.proofs.length === 0 ||
    !envelope.query_result
  ) {
    return { verified: false }
  }
  if (input.circuit_version !== "0.20.0") {
    return { verified: false }
  }

  const issuer = new URL(input.challenge_issuer)
  const domain = issuer.host
  const binding = challengeBinding(input)
  const zkPassport = new ZKPassport(domain)
  const { query } = zkPassport
    .createQuery()
    .disclose("nationality")
    .bind("custom_data", binding)
    .done()

  const result = await zkPassport.verify({
    proofs: envelope.proofs,
    originalQuery: query,
    queryResult: envelope.query_result,
    validity: 300,
    scope: input.challenge_scope,
    devMode: false,
    writingDirectory: process.env.ZKPASSPORT_TMP_DIR || "/tmp",
  })
  if (!result.verified || !result.uniqueIdentifier) {
    return { verified: false }
  }
  const disclosedNationality = alpha3(
    envelope.query_result?.nationality?.disclose?.result,
  )
  if (!disclosedNationality || disclosedNationality !== input.nationality) {
    return { verified: false }
  }
  return {
    verified: true,
    nationality: disclosedNationality,
    ...personhoodHashes(result.uniqueIdentifier),
  }
}
