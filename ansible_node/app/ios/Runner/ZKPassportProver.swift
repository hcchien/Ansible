import Foundation
import Swoir
import Swoirenberg

/// Narrow, UI-independent bridge to the pinned ZKPassport UltraHonk backend.
/// Artifact download and hash verification happen in Dart before paths reach
/// this class. This class never performs network I/O or persists witnesses.
final class ZKPassportProver {
  private let swoir = Swoir(backend: Swoirenberg.self)
  private var circuits: [String: Circuit] = [:]
  private let queue = DispatchQueue(label: "cool.elix.zkpassport.prover", qos: .userInitiated)

  func prepare(manifestJSON: String, circuitSize: UInt32, srsPath: String,
               completion: @escaping (Result<String, Error>) -> Void) {
    queue.async {
      autoreleasepool {
        do {
          let circuit = try self.swoir.createCircuit(
            manifest: Data(manifestJSON.utf8),
            size: circuitSize,
            lowMemoryMode: false,
            storageCap: 0
          )
          guard !srsPath.isEmpty else {
            throw ProverError.missingSRS
          }
          circuit.num_points = try Swoirenberg.setup_srs(
            circuit_size: 1_048_576,
            srs_path: srsPath
          )
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
          completion(.success(try circuit.verify(proof, vkey: verificationKey)))
        } catch {
          completion(.failure(error))
        }
      }
    }
  }

  func clear() {
    queue.sync { circuits.removeAll() }
  }

  enum ProverError: Error {
    case unknownCircuit
    case missingSRS
    case invalidProof
  }
}
