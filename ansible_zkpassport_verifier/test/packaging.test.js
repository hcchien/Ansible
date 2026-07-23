import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

test("server keeps ZKPassport external so bb.js can resolve its WASM", async () => {
  const bundle = await readFile(
    new URL("../dist/server.cjs", import.meta.url),
    "utf8",
  )

  assert.match(bundle, /require\(["']@zkpassport\/sdk["']\)/)
  assert.doesNotMatch(bundle, /barretenberg-threads\.wasm\.gz/)
})
