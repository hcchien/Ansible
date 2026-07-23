import Foundation
import WebKit

/// Ephemeral, on-device JavaScript runtime for the pinned ZKPassport parser
/// and circuit-input generator. It may fetch public registry artifacts, but
/// never navigates to remote content and uses no persistent website storage.
@available(iOS 15.0, *)
final class ZKPassportInputRuntime: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  private static let resultHandlerName = "elixZkPassportPlan"

  private var webView: WKWebView?
  private var planCompletion: ((Result<[String: Any], Error>) -> Void)?
  private var timeoutWorkItem: DispatchWorkItem?

  @MainActor
  func createProofPlan(
    runtimeJavaScript: String,
    request: [String: Any],
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
          const send = (payload) => {
            window.webkit.messageHandlers.\(Self.resultHandlerName).postMessage(
              JSON.stringify(payload)
            );
          };
          Promise.resolve().then(async () => {
            const runtime = globalThis.ElixZKPassport;
            if (!runtime || typeof runtime.createProofPlan !== "function") {
              throw new Error("ZKPassport runtime did not install its global API");
            }
            const plan = await runtime.createProofPlan(\(requestJSON));
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
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    webView?.configuration.userContentController.removeScriptMessageHandler(
      forName: Self.resultHandlerName
    )
    webView = nil
    completion(result)
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
