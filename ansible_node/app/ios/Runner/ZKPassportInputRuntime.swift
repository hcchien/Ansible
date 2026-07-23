import Foundation
import WebKit

/// Ephemeral, on-device JavaScript runtime for the pinned ZKPassport parser
/// and circuit-input generator. It may fetch public registry artifacts, but
/// never navigates to remote content and uses no persistent website storage.
@available(iOS 15.0, *)
final class ZKPassportInputRuntime: NSObject, WKNavigationDelegate {
  private var webView: WKWebView?

  @MainActor
  func createProofPlan(
    runtimeJavaScript: String,
    request: [String: Any],
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    self.webView = webView
    webView.loadHTMLString("<!doctype html><meta charset=\"utf-8\">", baseURL: nil)

    func waitUntilReady(_ attempts: Int) {
      guard attempts > 0 else {
        completion(.failure(RuntimeError.initializationFailed))
        self.webView = nil
        return
      }
      webView.evaluateJavaScript("document.readyState") { _, error in
        if error != nil {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitUntilReady(attempts - 1)
          }
          return
        }
        webView.evaluateJavaScript(runtimeJavaScript) { _, loadError in
          if let loadError {
            completion(.failure(loadError))
            self.webView = nil
            return
          }
          Task { @MainActor in
            defer { self.webView = nil }
            do {
              let value = try await webView.callAsyncJavaScript(
                """
                try {
                  const plan = await ElixZKPassport.createProofPlan(request);
                  return JSON.stringify({ ok: true, plan }, (_key, value) => {
                    if (typeof value === "bigint") return value.toString(10);
                    if (ArrayBuffer.isView(value)) return Array.from(value);
                    return value;
                  });
                } catch (error) {
                  return JSON.stringify({
                    ok: false,
                    error: String(error?.message || error || "Unknown JavaScript error"),
                  });
                }
                """,
                arguments: ["request": request],
                in: nil,
                contentWorld: .page
              )
              guard let encoded = value as? String,
                    let data = encoded.data(using: .utf8),
                    let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(RuntimeError.invalidPlan))
                return
              }
              guard envelope["ok"] as? Bool == true else {
                completion(.failure(RuntimeError.javaScript(
                  envelope["error"] as? String ?? "Unknown JavaScript error"
                )))
                return
              }
              guard let plan = envelope["plan"] as? [String: Any] else {
                completion(.failure(RuntimeError.invalidPlan))
                return
              }
              completion(.success(plan))
            } catch {
              let cocoaError = error as NSError
              let message =
                cocoaError.userInfo["WKJavaScriptExceptionMessage"] as? String ??
                cocoaError.localizedDescription
              completion(.failure(RuntimeError.javaScript(message)))
            }
          }
        }
      }
    }
    waitUntilReady(20)
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
    case initializationFailed
    case invalidPlan
    case javaScript(String)

    var errorDescription: String? {
      switch self {
      case .initializationFailed:
        return "ZKPassport JavaScript runtime initialization failed."
      case .invalidPlan:
        return "ZKPassport JavaScript runtime returned an invalid proof plan."
      case .javaScript(let message):
        return message
      }
    }
  }
}
