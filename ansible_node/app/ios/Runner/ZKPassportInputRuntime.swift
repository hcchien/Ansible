import Foundation
import JavaScriptCore

private struct CircuitPackageArtifact: Sendable {
  let data: Data
  let cacheHit: Bool
}

private actor CircuitPackageArtifactManager {
  private static let maximumPackageBytes = 25 * 1024 * 1024
  private static let sourceTimeoutNanoseconds: UInt64 = 15_000_000_000

  private let fileManager: FileManager
  private let cacheDirectory: URL
  private let session: URLSession

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
    let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ??
      fileManager.temporaryDirectory
    cacheDirectory = caches.appendingPathComponent(
      "ElixZKPassportCircuits-v0.20.0",
      isDirectory: true
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 15
    configuration.httpMaximumConnectionsPerHost = 5
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.waitsForConnectivity = false
    session = URLSession(configuration: configuration)
  }

  func load(
    name: String,
    expectedHash: String,
    urls: [URL]
  ) async throws -> CircuitPackageArtifact {
    let normalizedHash = Self.normalizeHash(expectedHash)
    guard normalizedHash.count == 64,
          normalizedHash.allSatisfy(\.isHexDigit) else {
      throw ArtifactError.invalidIdentity
    }
    if let bundledURL = urls.first(where: { $0.scheme == "elix-asset" }) {
      let relativePath = bundledURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      guard let frameworkURL = Bundle.main.privateFrameworksURL?
              .appendingPathComponent("App.framework", isDirectory: true),
            !relativePath.contains("..") else {
        throw ArtifactError.invalidPackage
      }
      let assetURL = frameworkURL
        .appendingPathComponent("flutter_assets", isDirectory: true)
        .appendingPathComponent(relativePath, isDirectory: false)
      let data = try Data(contentsOf: assetURL)
      try validate(data, name: name, expectedHash: normalizedHash)
      return CircuitPackageArtifact(data: data, cacheHit: true)
    }
    try fileManager.createDirectory(
      at: cacheDirectory,
      withIntermediateDirectories: true
    )
    let cacheURL = cacheDirectory.appendingPathComponent(
      "\(normalizedHash).json",
      isDirectory: false
    )
    if let cached = try? Data(contentsOf: cacheURL),
       (try? validate(cached, name: name, expectedHash: normalizedHash)) != nil {
      return CircuitPackageArtifact(data: cached, cacheHit: true)
    }
    try? fileManager.removeItem(at: cacheURL)

    var lastError: Error = ArtifactError.noSources
    for url in urls {
      do {
        let data = try await fetch(url)
        try validate(data, name: name, expectedHash: normalizedHash)
        try data.write(to: cacheURL, options: [.atomic, .completeFileProtection])
        return CircuitPackageArtifact(data: data, cacheHit: false)
      } catch {
        lastError = error
      }
    }
    throw lastError
  }

  private func fetch(_ url: URL) async throws -> Data {
    let session = session
    return try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
          throw ArtifactError.httpStatus(
            (response as? HTTPURLResponse)?.statusCode ?? -1
          )
        }
        guard data.count <= Self.maximumPackageBytes else {
          throw ArtifactError.responseTooLarge
        }
        return data
      }
      group.addTask {
        try await Task.sleep(nanoseconds: Self.sourceTimeoutNanoseconds)
        throw ArtifactError.timedOut
      }
      defer { group.cancelAll() }
      guard let data = try await group.next() else {
        throw ArtifactError.timedOut
      }
      return data
    }
  }

  private func validate(
    _ data: Data,
    name: String,
    expectedHash: String
  ) throws {
    guard data.count <= Self.maximumPackageBytes,
          let package = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          package["name"] as? String == name,
          Self.normalizeHash(package["vkey_hash"] as? String ?? "") == expectedHash,
          package["hash"] as? String != nil,
          package["noir_version"] as? String != nil,
          package["bb_version"] as? String != nil else {
      throw ArtifactError.invalidPackage
    }
  }

  private static func normalizeHash(_ value: String) -> String {
    var normalized = value.lowercased()
    if normalized.hasPrefix("0x") {
      normalized.removeFirst(2)
    }
    return String(repeating: "0", count: max(0, 64 - normalized.count)) + normalized
  }

  private enum ArtifactError: LocalizedError {
    case httpStatus(Int)
    case invalidIdentity
    case invalidPackage
    case noSources
    case responseTooLarge
    case timedOut

    var errorDescription: String? {
      switch self {
      case .httpStatus(let status):
        return "Circuit source returned HTTP \(status)."
      case .invalidIdentity:
        return "Circuit identity is invalid."
      case .invalidPackage:
        return "Circuit package does not match the pinned identity."
      case .noSources:
        return "No circuit package source is available."
      case .responseTooLarge:
        return "Circuit package exceeds the allowed size."
      case .timedOut:
        return "Circuit package source timed out."
      }
    }
  }
}

/// In-process JavaScriptCore runtime for the reviewed ZKPassport parser and
/// witness-input generator. It has no DOM, website storage, navigation, or
/// network API. Swift resolves and verifies every public circuit artifact
/// after the private input descriptor has been generated.
@available(iOS 15.0, *)
final class ZKPassportInputRuntime: @unchecked Sendable {
  private var planCompletion: ((Result<[String: Any], Error>) -> Void)?
  private var planProgress: ((String) -> Void)?
  private var timeoutWorkItem: DispatchWorkItem?
  private var runtimeContext: JSContext?
  private var planTask: Task<Void, Never>?
  private let artifactManager = CircuitPackageArtifactManager()
  private let runtimeQueue = DispatchQueue(
    label: "cool.elix.zkpassport.planner",
    qos: .userInitiated
  )

  @MainActor
  func createProofPlan(
    runtimeJavaScript: String,
    request: [String: Any],
    progress: @escaping (String) -> Void,
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    guard planCompletion == nil else {
      completion(.failure(RuntimeError.alreadyRunning))
      return
    }

    guard JSONSerialization.isValidJSONObject(request) else {
      completion(.failure(RuntimeError.invalidRequest))
      return
    }

    planCompletion = completion
    planProgress = progress

    let timeout = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        self?.finish(.failure(RuntimeError.timedOut))
      }
    }
    timeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: timeout)
    runtimeQueue.async { [weak self] in
      self?.runJavaScriptCore(
        runtimeJavaScript: runtimeJavaScript,
        request: request
      )
    }
  }

  private func runJavaScriptCore(
    runtimeJavaScript: String,
    request: [String: Any]
  ) {
    guard let context = JSContext() else {
      finishOnMain(.failure(RuntimeError.initializationFailed))
      return
    }
    runtimeContext = context
    var uncaughtException: String?
    context.exceptionHandler = { _, exception in
      uncaughtException = Self.describeJavaScriptError(exception)
    }
    context.evaluateScript(Self.javaScriptCorePolyfills)
    context.evaluateScript(runtimeJavaScript)
    if let uncaughtException {
      finishOnMain(.failure(RuntimeError.javaScript(uncaughtException)))
      return
    }
    guard let runtime = context.objectForKeyedSubscript("ElixZKPassport"),
          !runtime.isUndefined,
          let createProofPlan = runtime.objectForKeyedSubscript("createProofPlan"),
          !createProofPlan.isUndefined,
          let normalize = context.evaluateScript(
            """
            (value) => JSON.stringify(value, (_key, item) => {
              if (typeof item === "bigint") return item.toString(10);
              if (ArrayBuffer.isView(item)) return Array.from(item);
              return item;
            })
            """
          ) else {
      finishOnMain(.failure(RuntimeError.initializationFailed))
      return
    }

    let progressBlock: @convention(block) (String) -> Void = { [weak self] stage in
      DispatchQueue.main.async {
        self?.planProgress?(stage)
      }
    }
    let successBlock: @convention(block) (JSValue) -> Void = { [weak self] value in
      guard let encoded = normalize.call(withArguments: [value])?.toString(),
            let data = encoded.data(using: .utf8),
            let descriptor = try? JSONSerialization.jsonObject(with: data)
              as? [String: Any] else {
        self?.finishOnMain(.failure(RuntimeError.invalidPlan))
        return
      }
      self?.resolveArtifacts(in: descriptor)
    }
    let failureBlock: @convention(block) (JSValue) -> Void = { [weak self] error in
      self?.finishOnMain(.failure(RuntimeError.javaScript(
        Self.describeJavaScriptError(error)
      )))
    }
    guard let promise = createProofPlan.call(
      withArguments: [request, progressBlock]
    ), !promise.isUndefined,
      let chained = promise.invokeMethod("then", withArguments: [successBlock]),
      !chained.isUndefined else {
      finishOnMain(.failure(RuntimeError.initializationFailed))
      return
    }
    chained.invokeMethod("catch", withArguments: [failureBlock])
  }

  private func resolveArtifacts(in descriptor: [String: Any]) {
    planTask = Task { [weak self, artifactManager] in
      guard let self else { return }
      do {
        guard let rawCircuits = descriptor["circuits"] as? [[String: Any]],
              (6...7).contains(rawCircuits.count) else {
          throw RuntimeError.invalidPlan
        }
        var resolved = Array<[String: Any]?>(repeating: nil, count: rawCircuits.count)
        try await withThrowingTaskGroup(
          of: (Int, CircuitPackageArtifact).self
        ) { group in
          for (index, circuit) in rawCircuits.enumerated() {
            guard let name = circuit["name"] as? String,
                  let expectedHash = circuit["expected_hash"] as? String,
                  let rawURLs = circuit["urls"] as? [String],
                  !rawURLs.isEmpty else {
              throw RuntimeError.invalidPlan
            }
            let urls = rawURLs.compactMap(URL.init(string:))
              .filter(Self.isAllowedPackageURL)
            guard urls.count == rawURLs.count else {
              throw RuntimeError.invalidPlan
            }
            group.addTask {
              let artifact = try await artifactManager.load(
                name: name,
                expectedHash: expectedHash,
                urls: urls
              )
              return (index, artifact)
            }
          }
          for try await (index, artifact) in group {
            guard var package = try JSONSerialization.jsonObject(
              with: artifact.data
            ) as? [String: Any] else {
              throw RuntimeError.invalidPlan
            }
            let descriptorCircuit = rawCircuits[index]
            package["manifest"] = package
            package["inputs"] = descriptorCircuit["inputs"]
            package["committed_inputs"] =
              descriptorCircuit["committed_inputs"] ?? [String: Any]()
            resolved[index] = package
            let name = descriptorCircuit["name"] as? String ?? "circuit"
            await MainActor.run {
              self.planProgress?(
                "\(artifact.cacheHit ? "cache" : "network"):\(name)"
              )
            }
          }
        }
        guard resolved.allSatisfy({ $0 != nil }) else {
          throw RuntimeError.invalidPlan
        }
        var plan = descriptor
        plan["circuits"] = resolved.compactMap { $0 }
        let completedPlan = plan
        await MainActor.run {
          self.finish(.success(completedPlan))
        }
      } catch {
        await MainActor.run {
          self.finish(.failure(error))
        }
      }
    }
  }

  private func finishOnMain(_ result: Result<[String: Any], Error>) {
    DispatchQueue.main.async { [weak self] in
      self?.finish(result)
    }
  }

  @MainActor
  private func finish(_ result: Result<[String: Any], Error>) {
    guard let completion = planCompletion else { return }
    planCompletion = nil
    planProgress = nil
    planTask?.cancel()
    planTask = nil
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    runtimeContext = nil
    completion(result)
  }

  private static func isAllowedPackageURL(_ url: URL) -> Bool {
    if url.scheme == "elix-asset" {
      return url.host == nil && url.query == nil && url.fragment == nil &&
        url.path.hasPrefix("/assets/zkpassport/circuits/") &&
        !url.path.contains("..")
    }
    guard url.scheme == "https", url.query == nil, url.fragment == nil else {
      return false
    }
    if url.host == "circuits2.zkpassport.id" {
      return url.path.hasPrefix("/mainnet/by-hash/") && url.path.hasSuffix(".json")
    }
    if url.host == "ipfs.zkpassport.id" {
      return url.path.hasPrefix("/ipfs/")
    }
    return false
  }

  private static func describeJavaScriptError(_ error: JSValue?) -> String {
    guard let error else {
      return "Unknown JavaScriptCore error"
    }
    let message = error.toString() ?? "Unknown JavaScriptCore error"
    guard let stack = error.objectForKeyedSubscript("stack"),
          !stack.isUndefined,
          !stack.isNull,
          let stackText = stack.toString(),
          !stackText.isEmpty,
          stackText != message else {
      return message
    }
    return "\(message)\n\(stackText)"
  }

  private static let javaScriptCorePolyfills = """
  (() => {
    if (typeof globalThis.TextEncoder === "undefined") {
      globalThis.TextEncoder = class {
        encode(value = "") {
          const encoded = unescape(encodeURIComponent(String(value)));
          return Uint8Array.from(encoded, character => character.charCodeAt(0));
        }
      };
    }
    if (typeof globalThis.TextDecoder === "undefined") {
      globalThis.TextDecoder = class {
        decode(value = new Uint8Array()) {
          const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
          let binary = "";
          for (let offset = 0; offset < bytes.length; offset += 8192) {
            binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
          }
          return decodeURIComponent(escape(binary));
        }
      };
    }
    if (typeof globalThis.console === "undefined") {
      globalThis.console = { log() {}, warn() {}, error() {} };
    }
  })();
  """

  enum RuntimeError: LocalizedError {
    case alreadyRunning
    case initializationFailed
    case invalidPlan
    case invalidRequest
    case timedOut
    case javaScript(String)

    var errorDescription: String? {
      switch self {
      case .alreadyRunning:
        return "A ZKPassport proof plan is already running."
      case .initializationFailed:
        return "ZKPassport JavaScriptCore runtime initialization failed."
      case .invalidPlan:
        return "ZKPassport JavaScriptCore runtime returned an invalid proof plan."
      case .invalidRequest:
        return "ZKPassport JavaScriptCore runtime received an invalid request."
      case .timedOut:
        return "ZKPassport proof planning timed out."
      case .javaScript(let message):
        return message
      }
    }
  }
}
