import Foundation
import WebKit

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
  private var packageTasks: [String: URLSessionDataTask] = [:]
  private var packageTimeouts: [String: DispatchWorkItem] = [:]
  private lazy var packageSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 45
    configuration.timeoutIntervalForResource = 90
    configuration.httpMaximumConnectionsPerHost = 5
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    return URLSession(configuration: configuration)
  }()

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
          const loadPackage = ({ name, urls }) => new Promise((resolve, reject) => {
            const id = `package-${++nextPackageId}`;
            packageResolvers.set(id, { resolve, reject });
            send({ package_request: { id, name, urls } });
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
    packageTasks.values.forEach { $0.cancel() }
    packageTasks.removeAll()
    packageTimeouts.values.forEach { $0.cancel() }
    packageTimeouts.removeAll()
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
    downloadPackage(id: id, urls: urls, index: 0)
  }

  @MainActor
  private func downloadPackage(id: String, urls: [URL], index: Int) {
    guard index < urls.count else {
      resolvePackage(id: id, data: nil, error: "All circuit package sources failed")
      return
    }
    var request = URLRequest(url: urls[index])
    request.timeoutInterval = 30
    request.cachePolicy = .returnCacheDataElseLoad
    let task = packageSession.dataTask(with: request) { [weak self] data, response, error in
      Task { @MainActor in
        guard let self else { return }
        self.packageTimeouts.removeValue(forKey: id)?.cancel()
        self.packageTasks.removeValue(forKey: id)
        if let error {
          if index + 1 < urls.count {
            self.downloadPackage(id: id, urls: urls, index: index + 1)
          } else {
            self.resolvePackage(id: id, data: nil, error: error.localizedDescription)
          }
          return
        }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let data,
              data.count <= 25 * 1024 * 1024,
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
          if index + 1 < urls.count {
            self.downloadPackage(id: id, urls: urls, index: index + 1)
          } else {
            self.resolvePackage(id: id, data: nil, error: "Invalid circuit package response")
          }
          return
        }
        self.resolvePackage(id: id, data: data, error: nil)
      }
    }
    packageTasks[id] = task
    let deadline = DispatchWorkItem { [weak task] in task?.cancel() }
    packageTimeouts[id] = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: deadline)
    task.resume()
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
    guard let webView else { return }
    let idJSON = Self.jsonLiteral(id)
    let errorJSON = Self.jsonLiteral(error)
    let payloadJSON = Self.jsonLiteral(data?.base64EncodedString())
    webView.evaluateJavaScript(
      "globalThis.__elixResolveCircuitPackage(\(idJSON), \(payloadJSON), \(errorJSON))"
    )
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
