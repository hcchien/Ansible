import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const pinnedArtifacts = [
  {
    file: "../src/pinned-circuit-manifest-0.20.0.json",
    sha256: "79bf2cf7f45aa2cf70c6ac764520006d28789b81ac45b80d74d4b582c911289e",
    root: "0x1bcacb8abb52ef2834e4862b264e1209368ac8e006aa8512f6d62116e8657a46",
  },
  {
    file: "../src/pinned-certificates-mainnet.json",
    sha256: "495099fb98aab7499a3de7e4fa386b5a999c62c434fb7a4046280ff1798c94ec",
    root: "0x1a46d2abb5609cb22b62fa3275c85adefbf798cdb41407122f36801d50dd527f",
  },
]

test("bundled registry snapshots match reviewed roots and digests", async () => {
  for (const artifact of pinnedArtifacts) {
    const bytes = await readFile(new URL(artifact.file, import.meta.url))
    assert.equal(createHash("sha256").update(bytes).digest("hex"), artifact.sha256)
    assert.equal(JSON.parse(bytes).root, artifact.root)
  }
})

test("browser bundle injects Buffer into modules when the host has no Node globals", async () => {
  const bundle = await readFile(
    new URL("../../../assets/zkpassport/runtime.js", import.meta.url),
    "utf8",
  )
  const browser = {
    console,
    crypto: globalThis.crypto,
    fetch: globalThis.fetch,
    setTimeout,
    clearTimeout,
    TextDecoder,
    TextEncoder,
    URL,
    Uint8Array,
  }
  browser.globalThis = browser

  vm.runInNewContext(bundle, browser)

  assert.equal(typeof browser.ElixZKPassport?.createProofPlan, "function")
  assert.equal(
    browser.ElixZKPassport?.bufferCompatibilityCheck(),
    "454c4958",
  )
})

test("mobile planning returns pinned identities for native artifact resolution", async () => {
  const source = await readFile(
    new URL("../src/runtime.js", import.meta.url),
    "utf8",
  )

  assert.match(source, /expected_hash: expectedHash/)
  assert.match(source, /getServiceScopeHash\(request\.issuer_host\)/)
  assert.doesNotMatch(source, /new URL\(request\.issuer\)/)
  assert.match(source, /urls,/)
  assert.match(source, /selected:/)
  assert.match(source, /getDisclosedBytesFromMrzAndMask/)
  assert.match(source, /discloseMask: disclose\.inputs\.disclose_mask/)
  assert.match(source, /committed_inputs/)
  assert.match(source, /data: query\.bind/)
  assert.match(source, /age: \{ gte: 18 \}/)
  assert.match(source, /packaged\(manifest, "compare_age", report\)/)
  assert.match(source, /calculateAge\(passport\) >= 18/)
  assert.match(source, /passport\.nationality === "TWN"/)
  assert.match(source, /circuit !== null/)
  assert.doesNotMatch(source, /\.filter\(Boolean\)/)
  assert.doesNotMatch(source, /loadPackage/)
  assert.doesNotMatch(source, /RegistryClient/)
  assert.doesNotMatch(source, /validatePackagedCircuit/)
})
