import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

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
