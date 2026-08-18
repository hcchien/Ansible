package io.trisaura.ansible_node

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Local input planner hosted in the Android Rust process.
 *
 * No WebView, DOM, browser storage, or browser-network bridge exists in this
 * path. Circuit package fetching remains separate, on a strict HTTPS
 * allow-list, after private witness input generation. DG1/SOD and all witness
 * values remain in process only.
 */
internal class AndroidZkPassportInputRuntime(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val packages = CircuitPackages(context)

    fun createProofPlan(
        request: Map<*, *>,
        progress: (String) -> Unit,
        completion: (Result<Map<String, Any?>>) -> Unit,
    ) {
        val requestJson = try {
            AndroidZkJson.objectOf(request).toString()
        } catch (_: ZkPassportNativeException) {
            completion(Result.failure(ZkPassportNativeException("invalid_arguments")))
            return
        }
        Thread {
            try {
                val plan = AndroidZkPassportNative.plan(JSONObject(requestJson))
                progress("artifacts")
                val resolved = packages.resolve(plan)
                val flutter = AndroidZkJson.toFlutter(resolved) as? Map<String, Any?>
                    ?: throw ZkPassportNativeException("invalid_plan")
                main.post { completion(Result.success(flutter)) }
            } catch (error: ZkPassportNativeException) {
                main.post { completion(Result.failure(error)) }
            } catch (_: Throwable) {
                main.post { completion(Result.failure(ZkPassportNativeException("plan_failed"))) }
            }
        }.start()
    }

    private class CircuitPackages(private val context: Context) {
        fun resolve(plan: JSONObject): JSONObject {
            val circuits = plan.optJSONArray("circuits") ?: throw ZkPassportNativeException("invalid_plan")
            if (circuits.length() !in 6..7) throw ZkPassportNativeException("invalid_plan")
            val resolved = JSONArray()
            for (index in 0 until circuits.length()) {
                val descriptor = circuits.optJSONObject(index) ?: throw ZkPassportNativeException("invalid_plan")
                val name = descriptor.optString("name").takeIf { it.isNotEmpty() }
                    ?: throw ZkPassportNativeException("invalid_plan")
                val expected = normalizedHash(descriptor.optString("expected_hash"))
                val urls = descriptor.optJSONArray("urls") ?: throw ZkPassportNativeException("invalid_plan")
                val packageJson = load(name, expected, urls)
                val circuit = JSONObject(packageJson.toString())
                circuit.put("manifest", JSONObject(packageJson.toString()))
                circuit.put("inputs", descriptor.opt("inputs") ?: JSONObject.NULL)
                circuit.put("committed_inputs", descriptor.opt("committed_inputs") ?: JSONObject())
                resolved.put(circuit)
            }
            plan.put("circuits", resolved)
            return plan
        }

        private fun load(name: String, expectedHash: String, urls: JSONArray): JSONObject {
            val cache = File(context.cacheDir, "ElixZKPassportCircuits-v0.20.0/$expectedHash.json")
            cache.parentFile?.mkdirs()
            read(cache)?.let { validate(it, name, expectedHash); return JSONObject(String(it, Charsets.UTF_8)) }
            var last: ZkPassportNativeException = ZkPassportNativeException("artifact_unavailable")
            for (index in 0 until urls.length()) {
                val source = urls.optString(index)
                try {
                    val bytes = if (source.startsWith("elix-asset:///")) asset(source) else remote(source)
                    validate(bytes, name, expectedHash)
                    FileOutputStream(cache).use { it.write(bytes) }
                    return JSONObject(String(bytes, Charsets.UTF_8))
                } catch (error: ZkPassportNativeException) { last = error }
            }
            throw last
        }

        private fun asset(source: String): ByteArray {
            val path = source.removePrefix("elix-asset:///")
            if (!path.startsWith("assets/zkpassport/circuits/") || path.contains("..")) {
                throw ZkPassportNativeException("artifact_unavailable")
            }
            return context.assets.open("flutter_assets/$path").use { readLimited(it.readBytes()) }
        }

        private fun remote(source: String): ByteArray {
            val uri = URL(source)
            val allowed = uri.protocol == "https" && uri.query == null && uri.ref == null &&
                ((uri.host == "circuits2.zkpassport.id" && uri.path.startsWith("/mainnet/by-hash/") && uri.path.endsWith(".json")) ||
                    (uri.host == "ipfs.zkpassport.id" && uri.path.startsWith("/ipfs/")))
            if (!allowed) throw ZkPassportNativeException("artifact_unavailable")
            val connection = (uri.openConnection() as? HttpURLConnection) ?: throw ZkPassportNativeException("artifact_unavailable")
            connection.instanceFollowRedirects = false
            connection.connectTimeout = NETWORK_TIMEOUT_MS
            connection.readTimeout = NETWORK_TIMEOUT_MS
            connection.requestMethod = "GET"
            try {
                if (connection.responseCode != HttpURLConnection.HTTP_OK) throw ZkPassportNativeException("artifact_unavailable")
                return connection.inputStream.use { readLimited(it.readBytes()) }
            } finally { connection.disconnect() }
        }

        private fun read(file: File): ByteArray? = try { if (file.isFile) readLimited(file.readBytes()) else null } catch (_: Throwable) { null }
        private fun readLimited(bytes: ByteArray): ByteArray {
            if (bytes.size > MAX_PACKAGE_BYTES) throw ZkPassportNativeException("artifact_invalid")
            return bytes
        }

        private fun validate(bytes: ByteArray, name: String, expectedHash: String) {
            val packageJson = try { JSONObject(String(bytes, Charsets.UTF_8)) } catch (_: Throwable) { throw ZkPassportNativeException("artifact_invalid") }
            if (packageJson.optString("name") != name || normalizedHash(packageJson.optString("vkey_hash")) != expectedHash ||
                packageJson.optString("hash").isEmpty() || packageJson.optString("bytecode").isEmpty() ||
                packageJson.optString("vkey").isEmpty() || packageJson.optJSONObject("abi") == null ||
                packageJson.optString("noir_version").isEmpty() || packageJson.optString("bb_version").isEmpty()) {
                throw ZkPassportNativeException("artifact_invalid")
            }
        }

        private fun normalizedHash(value: String): String {
            val raw = value.removePrefix("0x").lowercase()
            if (!raw.matches(Regex("[0-9a-f]{1,64}"))) throw ZkPassportNativeException("artifact_invalid")
            return raw.padStart(64, '0')
        }
    }

    private companion object {
        const val NETWORK_TIMEOUT_MS = 15_000
        const val MAX_PACKAGE_BYTES = 25 * 1024 * 1024
    }
}

/** JSON conversion shared by the MethodChannel and the local planner. */
internal object AndroidZkJson {
    fun objectOf(value: Map<*, *>): JSONObject = JSONObject().also { json ->
        value.forEach { (key, item) ->
            if (key !is String) throw ZkPassportNativeException("invalid_arguments")
            json.put(key, valueOf(item))
        }
    }

    fun valueOf(value: Any?): Any? = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> objectOf(value)
        is Iterable<*> -> JSONArray().also { array -> value.forEach { array.put(valueOf(it)) } }
        is ByteArray -> JSONArray().also { array -> value.forEach { array.put(it.toInt() and 0xff) } }
        is String, is Boolean, is Int, is Long, is Double -> value
        else -> throw ZkPassportNativeException("invalid_arguments")
    }

    fun toFlutter(value: Any?): Any? = when (value) {
        is JSONObject -> buildMap { value.keys().forEach { key -> put(key, toFlutter(value.opt(key))) } }
        is JSONArray -> List(value.length()) { index -> toFlutter(value.opt(index)) }
        JSONObject.NULL -> null
        else -> value
    }
}
