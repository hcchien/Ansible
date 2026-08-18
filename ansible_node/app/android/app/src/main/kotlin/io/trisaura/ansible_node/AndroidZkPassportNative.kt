package io.trisaura.ansible_node

import android.util.Base64
import org.json.JSONObject

/**
 * Narrow Kotlin façade over the Rust/JNI UltraHonk backend.
 *
 * No passport data is logged or persisted here.  All errors are mapped to
 * safe category codes before returning through Flutter's method channel.
 */
internal object AndroidZkPassportNative {
    init {
        System.loadLibrary("elix_zkpassport")
    }

    private external fun call(operation: String, payload: String): String

    fun initializeSrs(circuitSize: Int, srsPath: String) {
        invoke("initialize_srs", JSONObject()
            .put("circuit_size", circuitSize)
            .put("srs_path", srsPath))
    }

    fun prepare(manifestJson: String, circuitSize: Int): String =
        invoke("prepare", JSONObject()
            .put("manifest_json", manifestJson)
            .put("circuit_size", circuitSize)) as String

    fun prove(circuitId: String, inputsJson: String, verificationKey: ByteArray): ByteArray {
        val value = invoke("prove", JSONObject()
            .put("circuit_id", circuitId)
            .put("inputs", JSONObject(inputsJson))
            .put("verification_key_base64", Base64.encodeToString(verificationKey, Base64.NO_WRAP))) as String
        return Base64.decode(value, Base64.DEFAULT)
    }

    fun verify(proof: ByteArray, verificationKey: ByteArray): Boolean =
        invoke("verify", JSONObject()
            .put("proof_base64", Base64.encodeToString(proof, Base64.NO_WRAP))
            .put("verification_key_base64", Base64.encodeToString(verificationKey, Base64.NO_WRAP))) as Boolean

    fun plan(request: JSONObject): JSONObject =
        (invoke("plan", JSONObject().put("request", request)) as? JSONObject)
            ?: throw ZkPassportNativeException("invalid_plan")

    fun plannerRuntimeSelfTest(): String =
        invoke("planner_runtime_self_test", JSONObject()) as? String
            ?: throw ZkPassportNativeException("planner_initialization_failed")

    fun clear() {
        invoke("clear", JSONObject())
    }

    private fun invoke(operation: String, payload: JSONObject): Any? {
        val response = JSONObject(call(operation, payload.toString()))
        if (!response.optBoolean("ok", false)) {
            throw ZkPassportNativeException(response.optString("code", "native_failed"))
        }
        return response.opt("value")
    }
}

internal class ZkPassportNativeException(val safeCode: String) : Exception(safeCode)
