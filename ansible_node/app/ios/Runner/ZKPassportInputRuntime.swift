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
                "return await ElixZKPassport.createProofPlan(request)",
                arguments: ["request": request],
                in: nil,
                contentWorld: .page
              )
              guard let plan = value as? [String: Any] else {
                completion(.failure(RuntimeError.invalidPlan))
                return
              }
              completion(.success(plan))
            } catch {
              completion(.failure(error))
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

  enum RuntimeError: Error {
    case initializationFailed
    case invalidPlan
  }
}
