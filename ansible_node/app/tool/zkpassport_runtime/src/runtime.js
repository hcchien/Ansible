import { sha256 } from "@noble/hashes/sha2.js"
import pinnedCertificates from "./pinned-certificates-mainnet.json"
import pinnedManifest from "./pinned-circuit-manifest-0.20.0.json"
import {
  Binary,
  OPRF_ZERO_PROOF,
  PassportReader,
  extractTBS,
  getBitSize,
  getBindCircuitInputs,
  getCscaForPassportAsync,
  getDisclosedBytesFromMrzAndMask,
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

async function packaged(manifest, name, report = () => {}) {
  const manifestEntry = manifest.circuits[name]
  const expectedHash = manifestEntry?.hash
  if (!expectedHash) throw new Error(`Circuit ${name} is absent from the pinned manifest`)
  const urls = [
    `https://circuits2.zkpassport.id/mainnet/by-hash/${expectedHash}.json`,
  ]
  if (manifestEntry.cid) {
    urls.push(`https://ipfs.zkpassport.id/ipfs/${manifestEntry.cid}`)
  }
  report(`selected:${name}`)
  return {
    name,
    expected_hash: expectedHash,
    urls,
    inputs: null,
  }
}

async function twPersonBindingCircuit(passport, salts, serviceScope, serviceSubscope, timestamp, report) {
  report("tw-person-binding:inputs")
  const inputs = await getDiscloseCircuitInputs(
    passport,
    {},
    salts,
    0n,
    serviceScope,
    serviceSubscope,
    timestamp,
    OPRF_ZERO_PROOF,
  )
  delete inputs.disclose_mask
  report("tw-person-binding:ready")
  return {
    name: "tw_person_binding",
    expected_hash: "02c79897440f6ec265c1c79a70f414e642d09fe464a2d1dbd1540cf586940c9e",
    urls: ["elix-asset:///assets/zkpassport/circuits/tw_person_binding.json"],
    inputs,
    committed_inputs: { tw_person_binding: { version: 1 } },
  }
}

async function buildDSCCircuit(
  passport,
  manifest,
  certificates,
  report,
) {
  report("dsc:select")
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
  const circuit = await packaged(manifest, name, report)
  report("dsc:inputs")
  circuit.inputs = await getDSCCircuitInputs(passport, privateState.salt, certificates)
  report("dsc:ready")
  return circuit
}

async function buildIDCircuit(passport, manifest, report) {
  report("id:select")
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
  const circuit = await packaged(manifest, name, report)
  report("id:inputs")
  circuit.inputs = await getIDDataCircuitInputs(
    passport,
    privateState.salt,
    privateState.salt,
  )
  report("id:ready")
  return circuit
}

const privateState = { salt: 0n }

export async function createProofPlan(
  request,
  report = () => {},
) {
  if (request.version !== "0.20.0") throw new Error("Unsupported circuit version")
  report("passport:parse")
  privateState.salt = BigInt(request.salt)
  const reader = new PassportReader()
  reader.loadPassport(Binary.from(request.dg1), Binary.from(request.sod))
  const passport = reader.getPassportViewModel()
  if (!isIDSupported(passport)) throw new Error("This passport is not supported by ZKPassport")
  report("passport:supported")

  // These public registry snapshots are reviewed and pinned by the signed app
  // release. Recomputing their 790-circuit and 584-certificate Merkle roots in
  // mobile WebKit dominated proof planning. Individual passport-specific
  // circuit packages remain downloaded on demand and checked against the
  // signed release's pinned circuit identity below. The issuer independently
  // verifies the resulting proof with its own registry verification key.
  const manifest = pinnedManifest
  const certificates = pinnedCertificates
  if (manifest.version !== request.version) {
    throw new Error("Pinned ZKPassport manifest version mismatch")
  }
  report("registry:ready")
  const salts = disclosureSalts(privateState.salt)
  const query = {
    nationality: { disclose: true },
    bind: { custom_data: request.challenge_binding },
  }
  if (!request.issuer_host) throw new Error("Issuer host is missing")
  const serviceScope = getServiceScopeHash(request.issuer_host)
  const serviceSubscope = getServiceSubscopeHash(request.scope)
  const timestamp = getNowTimestamp()

  const integrityName =
    `data_check_integrity_sa_${passport.sod.signerInfo.digestAlgorithm
      .toLowerCase()
      .replace("-", "")}_dg_${passport.sod.encapContentInfo.eContent.hashAlgorithm
      .toLowerCase()
      .replace("-", "")}`

  // Return pinned circuit identities with the private witness inputs. The
  // native app process resolves, validates, and caches the public packages
  // after JavaScriptCore completes; no WebKit or JavaScript network bridge is
  // involved.
  const [dsc, id, integrity, disclose, bind, twPersonBinding] = await Promise.all([
    buildDSCCircuit(
      passport,
      manifest,
      certificates,
      report,
    ),
    buildIDCircuit(passport, manifest, report),
    packaged(manifest, integrityName, report),
    packaged(manifest, "disclose_bytes", report),
    packaged(manifest, "bind", report),
    twPersonBindingCircuit(passport, salts, serviceScope, serviceSubscope, timestamp, report),
  ])
  report("integrity:inputs")
  integrity.inputs = await getIntegrityCheckCircuitInputs(passport, privateState.salt, salts)

  report("disclose:inputs")
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
  disclose.committed_inputs = {
    disclose_bytes: {
      discloseMask: disclose.inputs.disclose_mask,
      disclosedBytes: getDisclosedBytesFromMrzAndMask(
        passport.mrz,
        disclose.inputs.disclose_mask,
      ),
    },
  }
  report("bind:inputs")
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
  bind.committed_inputs = {
    bind: {
      data: query.bind,
    },
  }
  report("plan:ready")
  return {
    version: manifest.version,
    circuits: [dsc, id, integrity, disclose, bind, twPersonBinding],
    query_result: {
      nationality: { disclose: { result: passport.nationality } },
      bind: { custom_data: request.challenge_binding },
    },
  }
}

export function bufferCompatibilityCheck() {
  return Buffer.from([0x45, 0x4c, 0x49, 0x58]).toString("hex")
}

globalThis.ElixZKPassport = { createProofPlan, bufferCompatibilityCheck }
