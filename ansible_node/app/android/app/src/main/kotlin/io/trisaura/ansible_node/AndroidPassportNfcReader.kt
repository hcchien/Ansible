package io.trisaura.ansible_node

import android.app.Activity
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.os.Bundle
import io.flutter.plugin.common.MethodChannel
import net.sf.scuba.smartcards.IsoDepCardService
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.jmrtd.BACKey
import org.jmrtd.PACEKeySpec
import org.jmrtd.PassportService
import org.jmrtd.lds.CardAccessFile
import org.jmrtd.lds.PACEInfo
import org.jmrtd.lds.SODFile
import org.jmrtd.lds.icao.DG1File
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.security.Security
import java.security.Signature
import java.security.cert.CertPathBuilder
import java.security.cert.CertStore
import java.security.cert.CertificateFactory
import java.security.cert.CollectionCertStoreParameters
import java.security.cert.PKIXBuilderParameters
import java.security.cert.TrustAnchor
import java.security.cert.X509CertSelector
import java.security.cert.X509Certificate
import java.util.concurrent.Executors

/**
 * Narrow Android implementation of the same `elix/passport_nfc` boundary as
 * iOS. Raw APDUs, MRZ access data, DG1 and SOD remain in memory for one scan
 * only; this class never logs or persists any passport material.
 */
internal class AndroidPassportNfcReader(private val activity: Activity) {
    private val adapter: NfcAdapter? = NfcAdapter.getDefaultAdapter(activity)
    private val executor = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private var pending: MethodChannel.Result? = null
    private var request: ScanRequest? = null

    private data class ScanRequest(
        val documentNumber: String,
        val dateOfBirth: String,
        val dateOfExpiry: String,
        val trustedCscaPem: String,
    )

    fun isAvailable(): Boolean = adapter?.isEnabled == true

    fun scan(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val values = arguments ?: run {
            result.error("invalid_arguments", "Missing passport reader arguments.", null)
            return
        }
        val scanRequest = ScanRequest(
            documentNumber = values["document_number"] as? String ?: "",
            dateOfBirth = values["date_of_birth"] as? String ?: "",
            dateOfExpiry = values["date_of_expiry"] as? String ?: "",
            trustedCscaPem = values["trusted_csca_pem"] as? String ?: "",
        )
        if (scanRequest.documentNumber.isBlank() || scanRequest.dateOfBirth.length != 6 ||
            scanRequest.dateOfExpiry.length != 6 || scanRequest.trustedCscaPem.isBlank()) {
            result.error("invalid_arguments", "Missing MRZ access data or CSCA trust anchors.", null)
            return
        }
        val nfc = adapter
        if (nfc == null || !nfc.isEnabled) {
            result.error("passport_nfc_interrupted", "Passport NFC is unavailable.", null)
            return
        }
        synchronized(lock) {
            if (pending != null) {
                result.error("passport_scan_in_progress", "A passport scan is already in progress.", null)
                return
            }
            pending = result
            request = scanRequest
        }
        nfc.enableReaderMode(
            activity,
            { tag -> onTag(tag) },
            NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
            Bundle(),
        )
    }

    fun cancel() {
        completeError("passport_scan_cancelled", "Passport scan cancelled.")
    }

    private fun onTag(tag: Tag) {
        val scanRequest = synchronized(lock) { request } ?: return
        executor.execute {
            try {
                val value = readPassport(tag, scanRequest)
                completeSuccess(value)
            } catch (error: Throwable) {
                val (code, message) = mapError(error)
                completeError(code, message)
            }
        }
    }

    private fun readPassport(tag: Tag, scanRequest: ScanRequest): Map<String, Any> {
        val isoDep = IsoDep.get(tag) ?: throw IllegalStateException("unsupported_tag")
        val cardService = IsoDepCardService(isoDep)
        val service = PassportService(
            cardService,
            PassportService.NORMAL_MAX_TRANCEIVE_LENGTH,
            PassportService.DEFAULT_MAX_BLOCKSIZE,
            false,
            false,
        )
        try {
            service.open()
            val accessKey = BACKey(
                scanRequest.documentNumber,
                scanRequest.dateOfBirth,
                scanRequest.dateOfExpiry,
            )
            val paceSucceeded = tryPace(service, accessKey)
            service.sendSelectApplet(paceSucceeded)
            if (!paceSucceeded) service.doBAC(accessKey)

            val dg1Bytes = service.getInputStream(PassportService.EF_DG1).use(::readAll)
            val sodBytes = service.getInputStream(PassportService.EF_SOD).use(::readAll)
            val dg1 = DG1File(ByteArrayInputStream(dg1Bytes))
            val sod = SODFile(ByteArrayInputStream(sodBytes))
            val mrz = dg1.mrzInfo

            // Fail closed: all three checks must pass before Flutter will be
            // allowed to construct a proof or call the Issuer.
            val sodSignatureVerified = verifySodSignature(sod)
            val dg1HashVerified = verifyDataGroupHash(sod, 1, dg1Bytes)
            val cscaVerified = verifyCscaChain(sod, scanRequest.trustedCscaPem)
            if (!sodSignatureVerified || !dg1HashVerified || !cscaVerified) {
                throw SecurityException("passport_passive_authentication_failed")
            }
            return mapOf(
                "document_number" to mrz.documentNumber,
                "date_of_birth" to mrz.dateOfBirth,
                "date_of_expiry" to mrz.dateOfExpiry,
                "nationality" to mrz.nationality,
                "dg1" to dg1Bytes,
                "sod" to sodBytes,
                "sod_signature_verified" to true,
                "data_group_hashes_verified" to true,
                "country_signing_certificate_verified" to true,
                "active_authentication_verified" to false,
            )
        } finally {
            service.close()
        }
    }

    private fun tryPace(service: PassportService, accessKey: BACKey): Boolean {
        return try {
            val infos = service.getInputStream(PassportService.EF_CARD_ACCESS).use {
                CardAccessFile(it).securityInfos.filterIsInstance<PACEInfo>()
            }
            val paceKey = PACEKeySpec.createMRZKey(accessKey)
            infos.any { info ->
                try {
                    service.doPACE(
                        paceKey,
                        info.objectIdentifier,
                        PACEInfo.toParameterSpec(info.parameterId),
                        info.parameterId,
                    )
                    true
                } catch (_: Exception) {
                    false
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun verifyDataGroupHash(sod: SODFile, number: Int, encoded: ByteArray): Boolean {
        val expected = sod.dataGroupHashes[number] ?: return false
        return MessageDigest.getInstance(sod.digestAlgorithm).digest(encoded).contentEquals(expected)
    }

    private fun verifySodSignature(sod: SODFile): Boolean {
        val certificate = sod.docSigningCertificate ?: return false
        val algorithm = when (val raw = sod.digestEncryptionAlgorithm) {
            "RSA" -> sod.signerInfoDigestAlgorithm.replace("-", "") + "withRSA"
            "SSAwithRSA/PSS" -> return false // PSS parameters require an explicit profile; reject rather than guess.
            else -> raw
        }
        val provider = BouncyCastleProvider.PROVIDER_NAME
        if (Security.getProvider(provider) == null) Security.addProvider(BouncyCastleProvider())
        return try {
            Signature.getInstance(algorithm, provider).run {
                initVerify(certificate)
                update(sod.eContent)
                verify(sod.encryptedDigest)
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun verifyCscaChain(sod: SODFile, pem: String): Boolean {
        val documentSigner = sod.docSigningCertificate ?: return false
        val anchors = CertificateFactory.getInstance("X.509")
            .generateCertificates(ByteArrayInputStream(pem.toByteArray()))
            .filterIsInstance<X509Certificate>()
            .map { TrustAnchor(it, null) }
            .toSet()
        if (anchors.isEmpty()) return false
        return try {
            val selector = X509CertSelector().apply { certificate = documentSigner }
            val params = PKIXBuilderParameters(anchors, selector).apply {
                isRevocationEnabled = false
                addCertStore(
                    CertStore.getInstance(
                        "Collection",
                        CollectionCertStoreParameters(sod.docSigningCertificates),
                    ),
                )
            }
            CertPathBuilder.getInstance("PKIX").build(params)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun readAll(input: InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(4096)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) return output.toByteArray()
            output.write(buffer, 0, count)
        }
    }

    private fun completeSuccess(value: Map<String, Any>) = complete { it.success(value) }

    private fun completeError(code: String, message: String) = complete { it.error(code, message, null) }

    private fun complete(action: (MethodChannel.Result) -> Unit) {
        val result = synchronized(lock) {
            val current = pending
            pending = null
            request = null
            current
        } ?: return
        activity.runOnUiThread {
            adapter?.disableReaderMode(activity)
            action(result)
        }
    }

    private fun mapError(error: Throwable): Pair<String, String> = when {
        error.message == "unsupported_tag" -> "passport_nfc_unsupported_tag" to "The NFC tag is not an ePassport."
        error.message?.contains("passport_passive_authentication_failed") == true ->
            "passport_nfc_interrupted" to "Passport security verification failed."
        else -> "passport_nfc_interrupted" to "Passport NFC session was interrupted."
    }
}
