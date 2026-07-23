import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testZKPassportRuntimeUsesPinnedArtifactCacheAndSerializedDelivery() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Runner/ZKPassportInputRuntime.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertTrue(source.contains("ElixZKPassportCircuits-v0.20.0"))
    XCTAssertTrue(source.contains("completeFileProtection"))
    XCTAssertTrue(source.contains("sourceTimeoutNanoseconds"))
    XCTAssertTrue(source.contains("packageResolutionQueue"))
    XCTAssertTrue(source.contains("deliverNextPackageResolution"))
    XCTAssertFalse(source.contains("packageSession.dataTask"))
  }

}
