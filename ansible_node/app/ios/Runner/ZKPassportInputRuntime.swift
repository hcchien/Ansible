import Foundation
import WebKit

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

/// Ephemeral, on-device JavaScript runtime for the pinned ZKPassport parser
/// and circuit-input generator. Public circuit downloads use the constrained
/// native URLSession bridge below; WebKit never navigates to remote content
/// and uses no persistent website storage.
@available(iOS 15.0, *)
final class ZKPassportInputRuntime: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  private static let resultHandlerName = "elixZkPassportPlan"

  private var webView: WKWebView?
  private var planCompletion: ((Result<[String: Any], Error>) -> Void)?
  private var planProgress: ((String) -> Void)?
  private var timeoutWorkItem: DispatchWorkItem?
  private let artifactManager = CircuitPackageArtifactManager()
  private var packageLoadTasks: [String: Task<Void, Never>] = [:]
  private var packageResolutionQueue: [(id: String, data: Data?, error: String?)] = []
  private var isDeliveringPackageResolution = false

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

    let requestJSON: String
    do {
      let data = try JSONSerialization.data(withJSONObject: request)
      guard let encoded = String(data: data, encoding: .utf8) else {
        completion(.failure(RuntimeError.invalidRequest))
        return
      }
      requestJSON = encoded
    } catch {
      completion(.failure(RuntimeError.invalidRequest))
      return
    }

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.userContentController.add(
      self,
      name: Self.resultHandlerName
    )
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    self.webView = webView
    planCompletion = completion
    planProgress = progress

    let timeout = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        self?.finish(.failure(RuntimeError.timedOut))
      }
    }
    timeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: timeout)

    webView.loadHTMLString("<!doctype html><meta charset=\"utf-8\">", baseURL: nil)

    func waitUntilReady(_ attempts: Int) {
      guard attempts > 0 else {
        self.finish(.failure(RuntimeError.initializationFailed))
        return
      }
      webView.evaluateJavaScript("document.readyState") { _, error in
        if error != nil {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitUntilReady(attempts - 1)
          }
          return
        }

        // evaluateJavaScript only starts the async work. The durable script
        // message handler delivers the result later, avoiding WebKit dropping
        // callAsyncJavaScript's completion during long registry downloads.
        let invocation = runtimeJavaScript + "\n" + """
        (() => {
          const packageResolvers = new Map();
          let nextPackageId = 0;
          const send = (payload) => {
            window.webkit.messageHandlers.\(Self.resultHandlerName).postMessage(
              JSON.stringify(payload)
            );
          };
          globalThis.__elixResolveCircuitPackage = (id, payload, error) => {
            const pending = packageResolvers.get(id);
            if (!pending) return;
            packageResolvers.delete(id);
            if (error) pending.reject(new Error(String(error)));
            else pending.resolve(JSON.parse(atob(payload)));
          };
          const loadPackage = ({ name, expectedHash, urls }) => new Promise((resolve, reject) => {
            const id = `package-${++nextPackageId}`;
            packageResolvers.set(id, { resolve, reject });
            send({ package_request: { id, name, expected_hash: expectedHash, urls } });
          });
          Promise.resolve().then(async () => {
            const runtime = globalThis.ElixZKPassport;
            if (!runtime || typeof runtime.createProofPlan !== "function") {
              throw new Error("ZKPassport runtime did not install its global API");
            }
            const plan = await runtime.createProofPlan(
              \(requestJSON),
              (stage) => send({ progress: String(stage) }),
              loadPackage
            );
            const encodedPlan = JSON.stringify(plan, (_key, value) => {
              if (typeof value === "bigint") return value.toString(10);
              if (ArrayBuffer.isView(value)) return Array.from(value);
              return value;
            });
            send({ ok: true, plan: JSON.parse(encodedPlan) });
          }).catch((error) => {
            send({
              ok: false,
              error: String(error?.message || error || "Unknown JavaScript error"),
            });
          });
        })();
        """
        webView.evaluateJavaScript(invocation) { _, loadError in
          if let loadError {
            self.finish(.failure(RuntimeError.javaScript(
              Self.javaScriptMessage(from: loadError)
            )))
          }
        }
      }
    }
    waitUntilReady(20)
  }

  @MainActor
  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard message.name == Self.resultHandlerName,
          let encoded = message.body as? String,
          let data = encoded.data(using: .utf8),
          let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      finish(.failure(RuntimeError.invalidPlan))
      return
    }
    if let progress = envelope["progress"] as? String {
      planProgress?(progress)
      return
    }
    if let packageRequest = envelope["package_request"] as? [String: Any] {
      downloadPackage(packageRequest)
      return
    }
    guard envelope["ok"] as? Bool == true else {
      finish(.failure(RuntimeError.javaScript(
        envelope["error"] as? String ?? "Unknown JavaScript error"
      )))
      return
    }
    guard let plan = envelope["plan"] as? [String: Any] else {
      finish(.failure(RuntimeError.invalidPlan))
      return
    }
    finish(.success(plan))
  }

  @MainActor
  private func finish(_ result: Result<[String: Any], Error>) {
    guard let completion = planCompletion else {
      return
    }
    planCompletion = nil
    planProgress = nil
    packageLoadTasks.values.forEach { $0.cancel() }
    packageLoadTasks.removeAll()
    packageResolutionQueue.removeAll()
    isDeliveringPackageResolution = false
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    webView?.configuration.userContentController.removeScriptMessageHandler(
      forName: Self.resultHandlerName
    )
    webView = nil
    completion(result)
  }

  @MainActor
  private func downloadPackage(_ request: [String: Any]) {
    guard let id = request["id"] as? String,
          let name = request["name"] as? String,
          let expectedHash = request["expected_hash"] as? String,
          let rawURLs = request["urls"] as? [String],
          !rawURLs.isEmpty else {
      resolvePackage(
        id: request["id"] as? String ?? "",
        data: nil,
        error: "Missing circuit package URLs"
      )
      return
    }
    let urls = rawURLs.compactMap(URL.init(string:)).filter(Self.isAllowedPackageURL)
    guard urls.count == rawURLs.count else {
      resolvePackage(id: id, data: nil, error: "Rejected circuit package URL")
      return
    }
    packageLoadTasks[id] = Task { [weak self, artifactManager] in
      do {
        let artifact = try await artifactManager.load(
          name: name,
          expectedHash: expectedHash,
          urls: urls
        )
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard let self else { return }
          self.packageLoadTasks.removeValue(forKey: id)
          self.planProgress?("\(artifact.cacheHit ? "cache" : "network"):\(name)")
          self.resolvePackage(id: id, data: artifact.data, error: nil)
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard let self else { return }
          self.packageLoadTasks.removeValue(forKey: id)
          self.resolvePackage(id: id, data: nil, error: error.localizedDescription)
        }
      }
    }
  }

  private static func isAllowedPackageURL(_ url: URL) -> Bool {
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

  @MainActor
  private func resolvePackage(id: String, data: Data?, error: String?) {
    packageResolutionQueue.append((id: id, data: data, error: error))
    deliverNextPackageResolution()
  }

  @MainActor
  private func deliverNextPackageResolution() {
    guard !isDeliveringPackageResolution,
          !packageResolutionQueue.isEmpty,
          let webView else {
      return
    }
    isDeliveringPackageResolution = true
    let resolution = packageResolutionQueue.removeFirst()
    let idJSON = Self.jsonLiteral(resolution.id)
    let errorJSON = Self.jsonLiteral(resolution.error)
    let payloadJSON = Self.jsonLiteral(resolution.data?.base64EncodedString())
    webView.evaluateJavaScript(
      "globalThis.__elixResolveCircuitPackage(\(idJSON), \(payloadJSON), \(errorJSON))"
    ) { [weak self] _, evaluationError in
      Task { @MainActor in
        guard let self else { return }
        self.isDeliveringPackageResolution = false
        if let evaluationError {
          self.finish(.failure(RuntimeError.javaScript(
            Self.javaScriptMessage(from: evaluationError)
          )))
          return
        }
        self.deliverNextPackageResolution()
      }
    }
  }

  private static func jsonLiteral(_ value: String?) -> String {
    guard let value,
          let data = try? JSONSerialization.data(withJSONObject: [value]),
          let array = String(data: data, encoding: .utf8) else {
      return "null"
    }
    return String(array.dropFirst().dropLast())
  }

  private static func javaScriptMessage(from error: Error) -> String {
    let cocoaError = error as NSError
    return cocoaError.userInfo["WKJavaScriptExceptionMessage"] as? String ??
      cocoaError.localizedDescription
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    // Registry fetch() requests are subresources and do not pass here as
    // top-level navigation. Reject every attempted document navigation.
    if navigationAction.navigationType == .other,
       navigationAction.request.url?.scheme == "about" {
      decisionHandler(.allow)
    } else {
      decisionHandler(.cancel)
    }
  }

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
        return "ZKPassport JavaScript runtime initialization failed."
      case .invalidPlan:
        return "ZKPassport JavaScript runtime returned an invalid proof plan."
      case .invalidRequest:
        return "ZKPassport JavaScript runtime received an invalid request."
      case .timedOut:
        return "ZKPassport proof planning timed out."
      case .javaScript(let message):
        return message
      }
    }
  }
}
