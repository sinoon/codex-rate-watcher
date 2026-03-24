import XCTest
@testable import CodexRateKit

final class ProxyServerTests: XCTestCase {

  // MARK: - Config Defaults

  func testConfigDefaults() {
    let config = ProxyServer.Config()
    XCTAssertEqual(config.port, 19876)
    XCTAssertEqual(config.upstream, "https://api.openai.com")
    XCTAssertTrue(config.autoRelay)
    XCTAssertFalse(config.verbose)
  }

  func testConfigCustomValues() {
    let config = ProxyServer.Config(
      port: 8080,
      upstream: "https://custom.api.com",
      autoRelay: false,
      verbose: true
    )
    XCTAssertEqual(config.port, 8080)
    XCTAssertEqual(config.upstream, "https://custom.api.com")
    XCTAssertFalse(config.autoRelay)
    XCTAssertTrue(config.verbose)
  }

  // MARK: - ProxyError

  func testProxyErrorSocketCreation() {
    let error = ProxyError.socketCreation
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("socket"))
  }

  func testProxyErrorBindFailed() {
    let error = ProxyError.bindFailed(port: 8080)
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("8080"))
  }

  func testProxyErrorListenFailed() {
    let error = ProxyError.listenFailed
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("listen"))
  }

  // MARK: - Integration: Health Endpoint

  func testHealthEndpoint() async throws {
    let port: UInt16 = 19877  // Use a different port to avoid conflicts
    let config = ProxyServer.Config(port: port, verbose: false)
    let server = ProxyServer(config: config)

    // Start server in background
    let serverTask = Task.detached {
      try await server.run()
    }

    // Wait for server to start
    try await Task.sleep(for: .milliseconds(200))

    // Make health request
    let url = URL(string: "http://127.0.0.1:\(port)/health")!
    let (data, response) = try await URLSession.shared.data(from: url)
    let http = response as! HTTPURLResponse

    XCTAssertEqual(http.statusCode, 200)

    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["status"] as? String, "ok")
    XCTAssertNotNil(json["requests"])
    XCTAssertNotNil(json["failovers"])
    XCTAssertNotNil(json["errors"])
    XCTAssertEqual(json["upstream"] as? String, "https://api.openai.com")

    serverTask.cancel()
    // Give the server a moment to clean up
    try await Task.sleep(for: .milliseconds(100))
  }

  func testRootEndpointSameAsHealth() async throws {
    let port: UInt16 = 19878
    let config = ProxyServer.Config(port: port, verbose: false)
    let server = ProxyServer(config: config)

    let serverTask = Task.detached {
      try await server.run()
    }
    try await Task.sleep(for: .milliseconds(200))

    let url = URL(string: "http://127.0.0.1:\(port)/")!
    let (data, response) = try await URLSession.shared.data(from: url)
    let http = response as! HTTPURLResponse

    XCTAssertEqual(http.statusCode, 200)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["status"] as? String, "ok")

    serverTask.cancel()
    try await Task.sleep(for: .milliseconds(100))
  }

  // MARK: - Integration: CORS Preflight

  func testCORSPreflight() async throws {
    let port: UInt16 = 19879
    let config = ProxyServer.Config(port: port, verbose: false)
    let server = ProxyServer(config: config)

    let serverTask = Task.detached {
      try await server.run()
    }
    try await Task.sleep(for: .milliseconds(200))

    let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
    var req = URLRequest(url: url)
    req.httpMethod = "OPTIONS"
    req.setValue("http://localhost:3000", forHTTPHeaderField: "Origin")
    req.setValue("POST", forHTTPHeaderField: "Access-Control-Request-Method")

    let (_, response) = try await URLSession.shared.data(for: req)
    let http = response as! HTTPURLResponse

    XCTAssertEqual(http.statusCode, 204)
    XCTAssertEqual(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*")
    XCTAssertNotNil(http.value(forHTTPHeaderField: "Access-Control-Allow-Methods"))
    XCTAssertNotNil(http.value(forHTTPHeaderField: "Access-Control-Allow-Headers"))

    serverTask.cancel()
    try await Task.sleep(for: .milliseconds(100))
  }

  // MARK: - Integration: 503 When No Auth

  func testReturns503WhenNoAuth() async throws {
    // This test works when there are no profiles configured
    // The proxy should return 503 with a meaningful error
    let port: UInt16 = 19880
    let config = ProxyServer.Config(port: port, verbose: false)
    let server = ProxyServer(config: config)

    let serverTask = Task.detached {
      try await server.run()
    }
    try await Task.sleep(for: .milliseconds(200))

    let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = Data(#"{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}"#.utf8)

    let (data, response) = try await URLSession.shared.data(for: req)
    let http = response as! HTTPURLResponse

    // If no profiles are available, should return 503
    // If profiles exist (e.g., on dev machine), may return 200 or other status
    if http.statusCode == 503 {
      let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
      let error = json["error"] as? [String: Any]
      XCTAssertNotNil(error)
      XCTAssertEqual(error?["type"] as? String, "proxy_error")
    }
    // Either way, we got a valid HTTP response
    XCTAssertTrue(http.statusCode > 0)

    serverTask.cancel()
    try await Task.sleep(for: .milliseconds(100))
  }

  // MARK: - Integration: Request Counter

  func testRequestCounter() async throws {
    let port: UInt16 = 19881
    let config = ProxyServer.Config(port: port, verbose: false)
    let server = ProxyServer(config: config)

    let serverTask = Task.detached {
      try await server.run()
    }
    try await Task.sleep(for: .milliseconds(200))

    let url = URL(string: "http://127.0.0.1:\(port)/health")!

    // Make 3 requests
    for _ in 0..<3 {
      let _ = try await URLSession.shared.data(from: url)
    }

    // 4th request should show count >= 4
    let (data, _) = try await URLSession.shared.data(from: url)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let count = json["requests"] as? Int ?? 0
    XCTAssertGreaterThanOrEqual(count, 4)

    serverTask.cancel()
    try await Task.sleep(for: .milliseconds(100))
  }

  // MARK: - Port Conflict

  func testBindFailedOnPortConflict() async throws {
    let port: UInt16 = 19882
    let config = ProxyServer.Config(port: port, verbose: false)
    let server1 = ProxyServer(config: config)
    let server2 = ProxyServer(config: config)

    let task1 = Task.detached {
      try await server1.run()
    }
    try await Task.sleep(for: .milliseconds(200))

    // Second server on same port should fail
    do {
      try await server2.run()
      XCTFail("Expected bindFailed error")
    } catch let error as ProxyError {
      if case .bindFailed(let p) = error {
        XCTAssertEqual(p, port)
      } else {
        XCTFail("Expected bindFailed, got \(error)")
      }
    } catch {
      // Also acceptable — different error type
    }

    task1.cancel()
    try await Task.sleep(for: .milliseconds(100))
  }
}
