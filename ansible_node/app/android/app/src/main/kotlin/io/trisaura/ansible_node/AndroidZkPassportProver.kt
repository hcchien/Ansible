package io.trisaura.ansible_node

/**
 * Flutter MethodChannel adapter for the source-built Rust UltraHonk backend.
 *
 * Calls run on a worker thread because proof generation can take minutes.  The
 * adapter deliberately emits only stable error categories; exception text
 * could contain values derived from a private passport witness.
 */
internal class AndroidZkPassportProver {
    fun initializeSrs(arguments: Map<*, *>) {
        val size = arguments["circuit_size"] as? Int ?: throw ZkPassportNativeException("invalid_arguments")
        val path = arguments["srs_path"] as? String ?: throw ZkPassportNativeException("invalid_arguments")
        AndroidZkPassportNative.initializeSrs(size, path)
    }

    fun prepare(arguments: Map<*, *>): String {
        val manifest = arguments["manifest_json"] as? String ?: throw ZkPassportNativeException("invalid_arguments")
        val size = arguments["circuit_size"] as? Int ?: throw ZkPassportNativeException("invalid_arguments")
        return AndroidZkPassportNative.prepare(manifest, size)
    }

    fun prove(arguments: Map<*, *>): ByteArray {
        val id = arguments["circuit_id"] as? String ?: throw ZkPassportNativeException("invalid_arguments")
        val inputs = arguments["inputs"] as? Map<*, *> ?: throw ZkPassportNativeException("invalid_arguments")
        val verificationKey = arguments["verification_key"] as? ByteArray
            ?: throw ZkPassportNativeException("invalid_arguments")
        return AndroidZkPassportNative.prove(id, AndroidZkJson.objectOf(inputs).toString(), verificationKey)
    }

    fun verify(arguments: Map<*, *>): Boolean {
        val proof = arguments["proof"] as? ByteArray ?: throw ZkPassportNativeException("invalid_arguments")
        val verificationKey = arguments["verification_key"] as? ByteArray
            ?: throw ZkPassportNativeException("invalid_arguments")
        return AndroidZkPassportNative.verify(proof, verificationKey)
    }

    fun clear() = AndroidZkPassportNative.clear()

}
