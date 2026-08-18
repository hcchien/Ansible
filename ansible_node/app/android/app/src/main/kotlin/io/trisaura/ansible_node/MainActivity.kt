package io.trisaura.ansible_node

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import javax.crypto.KeyAgreement

// FlutterFragmentActivity (not FlutterActivity): the local_auth biometric
// prompt used by passkey registration requires a FragmentActivity host —
// with plain FlutterActivity registration fails at the device-auth step.
class MainActivity : FlutterFragmentActivity() {
    private val passportNfcReader by lazy { AndroidPassportNfcReader(this) }
    private val zkPassportProver by lazy { AndroidZkPassportProver() }
    private val zkPassportInputRuntime by lazy { AndroidZkPassportInputRuntime(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ansible_node/backup_policy"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareRemoteMirrorDirectory" -> {
                    val name = call.argument<String>("name")
                    if (name.isNullOrBlank()) {
                        result.error(
                            "invalid_arguments",
                            "Missing no-backup directory name",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val directory = File(noBackupFilesDir, name)
                    if (!directory.exists() && !directory.mkdirs()) {
                        result.error(
                            "backup_policy_failed",
                            "Could not create ${directory.absolutePath}",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    result.success(directory.absolutePath)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "elix/passport_nfc"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(passportNfcReader.isAvailable())
                "scan" -> passportNfcReader.scan(call.arguments as? Map<*, *>, result)
                "cancel" -> {
                    passportNfcReader.cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "elix/zkpassport_prover"
        ).setMethodCallHandler { call, result ->
            val arguments = call.arguments as? Map<*, *>
            if (arguments == null && call.method != "clear") {
                result.error("invalid_arguments", "Missing prover arguments", null)
                return@setMethodCallHandler
            }
            if (call.method == "plan") {
                zkPassportInputRuntime.createProofPlan(
                    arguments!!,
                    progress = { stage ->
                        flutterEngine.dartExecutor.binaryMessenger.let { messenger ->
                            MethodChannel(messenger, "elix/zkpassport_prover")
                                .invokeMethod("plan_progress", stage)
                        }
                    },
                ) { outcome ->
                    outcome.fold(
                        onSuccess = { result.success(it) },
                        onFailure = { error ->
                            val safeCode = (error as? ZkPassportNativeException)?.safeCode ?: "plan_failed"
                            result.error("zkpassport_prover_failed", safeCode, null)
                        },
                    )
                }
                return@setMethodCallHandler
            }
            // Never run the prover on the UI thread.  Raw exception messages
            // are intentionally not passed back to Flutter, as a parser error
            // can include witness-derived input.
            Thread {
                try {
                    val value: Any? = when (call.method) {
                        "initialize_srs" -> { zkPassportProver.initializeSrs(arguments!!); null }
                        "prepare" -> zkPassportProver.prepare(arguments!!)
                        "prove" -> zkPassportProver.prove(arguments!!)
                        "verify" -> zkPassportProver.verify(arguments!!)
                        "clear" -> { zkPassportProver.clear(); null }
                        else -> {
                            runOnUiThread { result.notImplemented() }
                            return@Thread
                        }
                    }
                    runOnUiThread { result.success(value) }
                } catch (error: ZkPassportNativeException) {
                    runOnUiThread {
                        result.error("zkpassport_prover_failed", error.safeCode, null)
                    }
                } catch (_: Throwable) {
                    runOnUiThread {
                        result.error("zkpassport_prover_failed", "native_failed", null)
                    }
                }
            }.start()
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "elix/hardware_identity_key"
        ).setMethodCallHandler { call, result ->
            val alias = call.argument<String>("alias")
            if (alias.isNullOrBlank()) {
                result.error("invalid_arguments", "Missing key alias", null)
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "generate" -> result.success(generateHardwareKey(alias))
                    "load" -> result.success(loadHardwareKey(alias))
                    "sign" -> {
                        val message = call.argument<ByteArray>("message")
                        if (message == null) result.error("invalid_arguments", "Missing message", null)
                        else result.success(signWithHardwareKey(alias, message))
                    }
                    "generateAgreement" -> result.success(generateHardwareAgreementKey(alias))
                    "loadAgreement" -> result.success(loadHardwareKey(alias))
                    "deriveAgreement" -> {
                        val peerPublicKeyHex = call.argument<String>("peer_public_key_hex")
                        if (peerPublicKeyHex == null) {
                            result.error("invalid_arguments", "Missing peer public key", null)
                        } else {
                            result.success(deriveHardwareAgreement(alias, peerPublicKeyHex))
                        }
                    }
                    "deleteAgreement" -> {
                        KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry(alias) }
                        result.success(null)
                    }
                    "delete" -> {
                        KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry(alias) }
                        result.success(null)
                    }
                    "verify" -> {
                        val message = call.argument<ByteArray>("message")
                        val publicKeyHex = call.argument<String>("public_key_hex")
                        val signatureHex = call.argument<String>("signature_hex")
                        if (message == null || publicKeyHex == null || signatureHex == null) {
                            result.error("invalid_arguments", "Missing verification input", null)
                        } else {
                            result.success(verifyP256(publicKeyHex, message, signatureHex))
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("hardware_key_failed", error.message, null)
            }
        }
    }

    private fun keySpec(alias: String, strongBox: Boolean): KeyGenParameterSpec {
        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                30,
                KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(30)
        }
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }
        return builder.build()
    }

    private fun agreementKeySpec(alias: String, strongBox: Boolean): KeyGenParameterSpec {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            error("Hardware-backed P-256 key agreement requires Android 12 or newer")
        }
        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_AGREE_KEY)
            .setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(
                30,
                KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL
            )
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }
        return builder.build()
    }

    private fun generateHardwareKey(alias: String): Map<String, Any> {
        loadHardwareKey(alias)?.let { return it }
        fun generate(strongBox: Boolean) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(keySpec(alias, strongBox))
                generateKeyPair()
            }
        }
        try { generate(true) } catch (_: StrongBoxUnavailableException) { generate(false) }
        return loadHardwareKey(alias) ?: error("Generated key is unavailable")
    }

    private fun generateHardwareAgreementKey(alias: String): Map<String, Any> {
        loadHardwareKey(alias)?.let { return it }
        fun generate(strongBox: Boolean) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(agreementKeySpec(alias, strongBox))
                generateKeyPair()
            }
        }
        try { generate(true) } catch (_: StrongBoxUnavailableException) { generate(false) }
        return loadHardwareKey(alias) ?: error("Generated agreement key is unavailable")
    }

    private fun deriveHardwareAgreement(alias: String, peerPublicKeyHex: String): ByteArray {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            error("Hardware-backed P-256 key agreement requires Android 12 or newer")
        }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val privateKey = store.getKey(alias, null) as? java.security.PrivateKey
            ?: error("Agreement key not found")
        val peerPublicKey = decodeP256PublicKey(peerPublicKeyHex)
        val secret = KeyAgreement.getInstance("ECDH", "AndroidKeyStore").run {
            init(privateKey)
            doPhase(peerPublicKey, true)
            generateSecret()
        }
        if (secret.size != 32) error("Unexpected P-256 shared secret length")
        return secret
    }

    private fun loadHardwareKey(alias: String): Map<String, Any>? {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val certificate = store.getCertificate(alias) ?: return null
        val privateKey = store.getKey(alias, null) as java.security.PrivateKey
        val info = KeyFactory.getInstance(privateKey.algorithm, "AndroidKeyStore")
            .getKeySpec(privateKey, KeyInfo::class.java)
        val level = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            when (info.securityLevel) {
                android.security.keystore.KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                android.security.keystore.KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "trusted_environment"
                else -> "unknown_hardware"
            }
        } else if (info.isInsideSecureHardware) "trusted_environment" else "software_keystore"
        val custody = if (level == "strongbox" || level == "trusted_environment") {
            "hardware"
        } else {
            "reduced_trust"
        }
        val encoded = (certificate.publicKey as java.security.interfaces.ECPublicKey).w
        val publicBytes = byteArrayOf(0x04) + unsigned32(encoded.affineX) + unsigned32(encoded.affineY)
        return mapOf(
            "algorithm" to "p256-sha256",
            "public_key_hex" to publicBytes.joinToString("") { "%02x".format(it) },
            "custody" to custody,
            "hardware_security_level" to level
        )
    }

    private fun signWithHardwareKey(alias: String, message: ByteArray): Map<String, Any> {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = store.getKey(alias, null) as? java.security.PrivateKey ?: error("Identity key not found")
        val bytes = Signature.getInstance("SHA256withECDSA").run {
            initSign(key); update(message); sign()
        }
        return mapOf(
            "algorithm" to "p256-sha256",
            "signature_hex" to bytes.joinToString("") { "%02x".format(it) }
        )
    }

    private fun unsigned32(value: java.math.BigInteger): ByteArray {
        val raw = value.toByteArray()
        val source = if (raw.size == 33 && raw[0] == 0.toByte()) raw.copyOfRange(1, 33) else raw
        return ByteArray(32 - source.size) + source
    }

    private fun verifyP256(publicKeyHex: String, message: ByteArray, signatureHex: String): Boolean {
        return try {
            val publicKey = decodeP256PublicKey(publicKeyHex)
            val signature = signatureHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
            Signature.getInstance("SHA256withECDSA").run {
                initVerify(publicKey)
                update(message)
                verify(signature)
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun decodeP256PublicKey(publicKeyHex: String): java.security.PublicKey {
        val x963 = publicKeyHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        require(x963.size == 65 && x963[0] == 0x04.toByte()) { "Invalid P-256 public key" }
        val params = java.security.AlgorithmParameters.getInstance("EC").apply {
            init(java.security.spec.ECGenParameterSpec("secp256r1"))
        }.getParameterSpec(java.security.spec.ECParameterSpec::class.java)
        val point = java.security.spec.ECPoint(
            java.math.BigInteger(1, x963.copyOfRange(1, 33)),
            java.math.BigInteger(1, x963.copyOfRange(33, 65))
        )
        return KeyFactory.getInstance("EC").generatePublic(
            java.security.spec.ECPublicKeySpec(point, params)
        )
    }
}
