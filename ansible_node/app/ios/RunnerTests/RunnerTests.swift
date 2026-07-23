import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testZKPassportRuntimeUsesPinnedNativeArtifactsWithoutWebKit() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Runner/ZKPassportInputRuntime.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertTrue(source.contains("ElixZKPassportCircuits-v0.20.0"))
    XCTAssertTrue(source.contains("completeFileProtection"))
    XCTAssertTrue(source.contains("sourceTimeoutNanoseconds"))
    XCTAssertTrue(source.contains("import JavaScriptCore"))
    XCTAssertTrue(source.contains("JSContext"))
    XCTAssertTrue(source.contains("resolveArtifacts"))
    XCTAssertFalse(source.contains("import WebKit"))
    XCTAssertFalse(source.contains("WKWebView"))
    XCTAssertFalse(source.contains("WKScriptMessageHandler"))
    XCTAssertFalse(source.contains("base64EncodedString"))
    XCTAssertFalse(source.contains("packageSession.dataTask"))
  }

}
