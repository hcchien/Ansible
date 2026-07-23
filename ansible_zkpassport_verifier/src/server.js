import http from "node:http"
import { verifyPassportRequest } from "./verifier.js"

const port = Number(process.env.PORT || "8080")
const server = http.createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/healthz") {
    response.writeHead(200).end("ok")
    return
  }
  if (request.method !== "POST" || request.url !== "/verify") {
    response.writeHead(404).end()
    return
  }
  try {
    let raw = ""
    for await (const chunk of request) {
      raw += chunk
      // A complete ZKPassport query contains five UltraHonk proofs. Keep a
      // strict cap, but leave enough room for the pinned circuit envelope.
      if (raw.length > 8_388_608) throw new Error("request too large")
    }
    const result = await verifyPassportRequest(JSON.parse(raw))
    response
      .writeHead(result.verified ? 200 : 401, {
        "content-type": "application/json",
        "cache-control": "no-store",
      })
      .end(JSON.stringify(result))
  } catch (error) {
    console.error("verification failed", error)
    response
      .writeHead(401, {
        "content-type": "application/json",
        "cache-control": "no-store",
      })
      .end(JSON.stringify({ verified: false }))
  }
})

server.requestTimeout = 120_000
server.headersTimeout = 5_000
server.listen(port, "0.0.0.0", () => {
  console.log(`ansible_zkpassport_verifier listening on :${port}`)
})
