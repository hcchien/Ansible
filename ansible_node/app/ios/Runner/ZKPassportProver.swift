import Foundation
import Swoir
import Swoirenberg

/// Narrow, UI-independent bridge to the pinned ZKPassport UltraHonk backend.
/// Artifact download and hash verification happen in Dart before paths reach
/// this class. This class never performs network I/O or persists witnesses.
final class ZKPassportProver {
  private let swoir = Swoir(backend: Swoirenberg.self)
  private var circuits: [String: Circuit] = [:]
  private var nativeProofs: [String: Data] = [:]
  private var srsPoints: UInt32 = 0
  private let queue = DispatchQueue(label: "cool.elix.zkpassport.prover", qos: .userInitiated)

  func initializeSrs(circuitSize: UInt32, srsPath: String,
                     completion: @escaping (Result<Void, Error>) -> Void) {
    queue.async {
      autoreleasepool {
        do {
          guard !srsPath.isEmpty else {
            throw ProverError.missingSRS
          }
          self.srsPoints = try Swoirenberg.setup_srs(
            circuit_size: circuitSize,
            srs_path: srsPath
          )
          completion(.success(()))
        } catch {
          completion(.failure(error))
        }
      }
    }
  }

  func prepare(manifestJSON: String, circuitSize: UInt32,
               completion: @escaping (Result<String, Error>) -> Void) {
    queue.async {
      autoreleasepool {
        do {
          guard self.srsPoints > 0 else {
            throw ProverError.missingSRS
          }
          let circuit = try self.swoir.createCircuit(
            manifest: Data(manifestJSON.utf8),
            size: circuitSize,
            lowMemoryMode: false,
            storageCap: 0
          )
          circuit.num_points = self.srsPoints
          let id = circuit.manifest.hash.description
          self.circuits[id] = circuit
          completion(.success(id))
        } catch {
          completion(.failure(error))
        }
      }
    }
  }

  func prove(circuitID: String, inputs: [String: Any], verificationKey: Data,
             completion: @escaping (Result<Data, Error>) -> Void) {
    queue.async {
      autoreleasepool {
        guard let circuit = self.circuits[circuitID] else {
          completion(.failure(ProverError.unknownCircuit))
          return
        }
        do {
          let encoded = try circuit.prove(inputs, proof_type: "ultra_honk", vkey: verificationKey)
          guard encoded.count > 4 else {
            throw ProverError.invalidProof
          }
          // Swoir verifies the exact byte layout it produced. The ZKPassport
          // SDK envelope omits noir_rs's 4-byte public-input-count prefix, so
          // retain the native form only until the local verification finishes.
          self.nativeProofs[circuitID] = encoded
          // noir_rs prefixes a 4-byte big-endian public-input count. The
          // ZKPassport SDK verifier expects the raw bb layout without it.
          completion(.success(Data(encoded.dropFirst(4))))
        } catch {
          completion(.failure(error))
        }
      }
    }
  }

  func verify(circuitID: String, proof: Data, verificationKey: Data,
              completion: @escaping (Result<Bool, Error>) -> Void) {
    queue.async {
      autoreleasepool {
        guard let circuit = self.circuits[circuitID] else {
          completion(.failure(ProverError.unknownCircuit))
          return
        }
        do {
          let nativeProof = self.nativeProofs.removeValue(forKey: circuitID) ?? proof
          completion(.success(try circuit.verify(nativeProof, vkey: verificationKey)))
        } catch {
          completion(.failure(error))
        }
      }
    }
  }

  func clear() {
    queue.sync {
      circuits.removeAll()
      nativeProofs.removeAll()
    }
  }

  enum ProverError: Error {
    case unknownCircuit
    case missingSRS
    case invalidProof
  }
}
