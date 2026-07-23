import { sha256 } from "@noble/hashes/sha2.js"
import { RegistryClient } from "@zkpassport/registry"
import { Buffer } from "buffer"
import {
  Binary,
  OPRF_ZERO_PROOF,
  PassportReader,
  extractTBS,
  getBitSize,
  getBindCircuitInputs,
  getCscaForPassportAsync,
  getDiscloseCircuitInputs,
  getDSCCircuitInputs,
  getECDSAInfo,
  getIDDataCircuitInputs,
  getIntegrityCheckCircuitInputs,
  getNowTimestamp,
  getRSAInfo,
  getRSAPSSParams,
  getServiceScopeHash,
  getServiceSubscopeHash,
  getSodSignatureAlgorithmType,
  getTBSMaxLen,
  isIDSupported,
} from "@zkpassport/utils"

// WebKit does not expose Node's Buffer global. Some transitive ZKPassport
// registry/ASN.1 paths still access it directly even in their browser build.
// Install the pinned browser polyfill before any proof-plan work begins.
globalThis.Buffer = Buffer

function bytesToBigInt(bytes) {
  let value = 0n
  for (const byte of bytes) value = (value << 8n) | BigInt(byte)
  return value
}

function disclosureSalts(privateSalt) {
  const hex = privateSalt.toString(16).padStart(2, "0")
  const publicSalt = bytesToBigInt(
    sha256(Uint8Array.from(hex.match(/.{1,2}/g).map((x) => Number.parseInt(x, 16)))),
  )
  return {
    dg1Salt: privateSalt,
    dg2HashSalt: publicSalt,
    expiryDateSalt: publicSalt,
    privateNullifierSalt: privateSalt,
  }
}

function cscHashAlgorithm(sod) {
  const algorithm = sod.certificate?.signatureAlgorithm
  const name = algorithm?.name?.toLowerCase() || ""
  if (name.includes("pss") && algorithm.parameters) {
    return getRSAPSSParams(algorithm.parameters.toBuffer()).hashAlgorithm
  }
  for (const bits of ["1", "224", "256", "384", "512"]) {
    if (name.includes(`sha${bits}`)) return `SHA-${bits}`
  }
  return "SHA-256"
}

function sodHashAlgorithm(passport) {
  const name = passport.sod.signerInfo.signatureAlgorithm.name.toLowerCase()
  for (const bits of ["1", "224", "256", "384", "512"]) {
    if (name.includes(`sha${bits}`)) return `sha${bits}`
  }
  return passport.sod.signerInfo.digestAlgorithm.toLowerCase().replace("-", "")
}

async function packaged(registry, manifest, name) {
  const circuit = await registry.getPackagedCircuit(name, manifest, { validate: true })
  return {
    name,
    size: circuit.size,
    manifest: circuit,
    vkey: circuit.vkey,
    vkey_hash: circuit.vkey_hash,
    inputs: null,
  }
}

async function buildDSCCircuit(passport, registry, manifest, certificates) {
  const csc = await getCscaForPassportAsync(passport.sod.certificate, certificates.certificates)
  if (!csc) throw new Error("The passport CSCA is absent from the trusted registry")
  const hash = cscHashAlgorithm(passport.sod).replace("SHA-", "sha").toLowerCase()
  const tbs = getTBSMaxLen(passport)
  let name
  if (csc.signature_algorithm.toLowerCase().includes("ecdsa")) {
    const curve = csc.public_key.curve
    const family = curve.includes("brainpool") ? "brainpool" : "nist"
    const curveName = curve
      .replace("brainpoolP", "")
      .replace("nist", "")
      .replace("-", "")
      .toLowerCase()
    name = `sig_check_dsc_tbs_${tbs}_ecdsa_${family}_${curveName}_${hash}`
  } else {
    const bits = getBitSize(BigInt(csc.public_key.modulus))
    const scheme = csc.signature_algorithm === "RSA-PSS" ? "pss" : "pkcs"
    name = `sig_check_dsc_tbs_${tbs}_rsa_${scheme}_${bits}_${hash}`
  }
  const circuit = await packaged(registry, manifest, name)
  circuit.inputs = await getDSCCircuitInputs(passport, privateState.salt, certificates)
  return circuit
}

async function buildIDCircuit(passport, registry, manifest) {
  const certificate = extractTBS(passport)
  if (!certificate) throw new Error("Passport document-signing certificate is missing")
  const tbs = getTBSMaxLen(passport)
  const signatureType = getSodSignatureAlgorithmType(passport)
  const hash = sodHashAlgorithm(passport)
  let name
  if (signatureType === "ECDSA") {
    const curve = getECDSAInfo(certificate.subjectPublicKeyInfo).curve
    const family = curve.includes("brainpool") ? "brainpool" : "nist"
    const curveName = curve
      .replace("brainpoolP", "")
      .replace("nist", "")
      .replace("-", "")
      .toLowerCase()
    name = `sig_check_id_data_tbs_${tbs}_ecdsa_${family}_${curveName}_${hash}`
  } else if (signatureType === "RSA") {
    const bits = getBitSize(getRSAInfo(certificate.subjectPublicKeyInfo).modulus)
    const pss = passport.sod.signerInfo.signatureAlgorithm.name.toLowerCase().includes("pss")
    const scheme = pss ? "pss" : "pkcs"
    const selectedHash = pss
      ? getRSAPSSParams(
          passport.sod.signerInfo.signatureAlgorithm.parameters.toBuffer(),
        ).hashAlgorithm.toLowerCase().replace("-", "")
      : hash
    name = `sig_check_id_data_tbs_${tbs}_rsa_${scheme}_${bits}_${selectedHash}`
  } else {
    throw new Error("Unsupported passport document-signing algorithm")
  }
  const circuit = await packaged(registry, manifest, name)
  circuit.inputs = await getIDDataCircuitInputs(
    passport,
    privateState.salt,
    privateState.salt,
  )
  return circuit
}

const privateState = { salt: 0n }

export async function createProofPlan(request) {
  if (request.version !== "0.20.0") throw new Error("Unsupported circuit version")
  privateState.salt = BigInt(request.salt)
  const reader = new PassportReader()
  reader.loadPassport(Binary.from(request.dg1), Binary.from(request.sod))
  const passport = reader.getPassportViewModel()
  if (!isIDSupported(passport)) throw new Error("This passport is not supported by ZKPassport")

  const registry = new RegistryClient({ chainId: 1 })
  const [manifest, certificates] = await Promise.all([
    registry.getCircuitManifest(undefined, { version: request.version, validate: true }),
    registry.getCertificates(undefined, { validate: true }),
  ])
  const salts = disclosureSalts(privateState.salt)
  const query = {
    nationality: { disclose: true },
    bind: { custom_data: request.challenge_binding },
  }
  const serviceScope = getServiceScopeHash(new URL(request.issuer).host)
  const serviceSubscope = getServiceSubscopeHash(request.scope)
  const timestamp = getNowTimestamp()

  const dsc = await buildDSCCircuit(passport, registry, manifest, certificates)
  const id = await buildIDCircuit(passport, registry, manifest)
  const integrityName =
    `data_check_integrity_sa_${passport.sod.signerInfo.digestAlgorithm
      .toLowerCase()
      .replace("-", "")}_dg_${passport.sod.encapContentInfo.eContent.hashAlgorithm
      .toLowerCase()
      .replace("-", "")}`
  const integrity = await packaged(registry, manifest, integrityName)
  integrity.inputs = await getIntegrityCheckCircuitInputs(passport, privateState.salt, salts)

  const disclose = await packaged(registry, manifest, "disclose_bytes")
  disclose.inputs = await getDiscloseCircuitInputs(
    passport,
    query,
    salts,
    0n,
    serviceScope,
    serviceSubscope,
    timestamp,
    OPRF_ZERO_PROOF,
  )
  const bind = await packaged(registry, manifest, "bind")
  bind.inputs = await getBindCircuitInputs(
    passport,
    query,
    salts,
    0n,
    serviceScope,
    serviceSubscope,
    timestamp,
    OPRF_ZERO_PROOF,
  )
  return {
    version: manifest.version,
    circuits: [dsc, id, integrity, disclose, bind],
    query_result: {
      nationality: { disclose: { result: passport.nationality } },
      bind: { custom_data: request.challenge_binding },
    },
  }
}

globalThis.ElixZKPassport = { createProofPlan }
