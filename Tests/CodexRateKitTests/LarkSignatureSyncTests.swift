import XCTest
@testable import CodexRateKit

final class LarkSignatureSyncTests: XCTestCase {

  func testSummaryUsesMergedTotalsByDefault() {
    let summary = LarkSignatureFormatter.summary(
      snapshot: makeSnapshot(),
      label: "Codex",
      useLocalSummary: false,
      timeZone: Self.shanghaiTimeZone
    )

    XCTAssertTrue(summary.contains("Codex 全设备"))
    XCTAssertTrue(summary.contains("今日149.7M/$52"))
    XCTAssertTrue(summary.contains("7天1.2B/$412"))
    XCTAssertTrue(summary.contains("30天8.1B/$3.2k"))
  }

  func testSummaryCanUseLocalSummaryWhenRequested() {
    let summary = LarkSignatureFormatter.summary(
      snapshot: makeSnapshot(),
      label: "Codex",
      useLocalSummary: true,
      timeZone: Self.shanghaiTimeZone
    )

    XCTAssertTrue(summary.contains("Codex 本机"))
    XCTAssertTrue(summary.contains("今日12.3M/$4.6"))
    XCTAssertTrue(summary.contains("7天98.8M/$33"))
    XCTAssertTrue(summary.contains("30天456.8M/$123"))
  }

  func testSummaryOmitsHeaderWhenLabelIsEmpty() {
    let summary = LarkSignatureFormatter.summary(
      snapshot: makeSnapshot(),
      label: "",
      useLocalSummary: false,
      timeZone: Self.shanghaiTimeZone
    )

    XCTAssertFalse(summary.contains("Codex"))
    XCTAssertFalse(summary.contains("本机"))
    XCTAssertFalse(summary.contains("全设备"))
    XCTAssertEqual(summary, "Token 今日149.7M/$52 · 7天1.2B/$412 · 30天8.1B/$3.2k")
  }

  func testSummaryFallsBackWhenSnapshotHasNoData() {
    let summary = LarkSignatureFormatter.summary(
      snapshot: TokenCostSnapshot(
        todayTokens: nil,
        todayCostUSD: nil,
        last7DaysTokens: nil,
        last7DaysCostUSD: nil,
        last30DaysTokens: nil,
        last30DaysCostUSD: nil,
        daily: [],
        updatedAt: Self.updatedAt
      ),
      label: "Codex",
      timeZone: Self.shanghaiTimeZone
    )

    XCTAssertEqual(summary, "Codex 本机 · 暂无 token 数据 · 16:08")
  }

  func testUpdateSlotSendsBearerTokenAndJSONBody() async throws {
    let session = makeSession(
      statusCode: 200,
      data: Data(#"{"success":true}"#.utf8)
    ) { request in
      XCTAssertEqual(request.url?.absoluteString, "https://l.garyyang.work/api/slot/update")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cred-123")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

      let body = try XCTUnwrap(Self.requestBody(from: request))
      let payload = try JSONSerialization.jsonObject(with: body) as? [String: String]
      XCTAssertEqual(payload?["slotId"], "slot-abc")
      XCTAssertEqual(payload?["value"], "hello")
    }

    let client = LarkSlotClient(
      baseURL: URL(string: "https://l.garyyang.work")!,
      session: session
    )

    try await client.updateSlot(
      credential: "cred-123",
      slotID: "slot-abc",
      value: "hello"
    )
  }

  func testUpdateSlotSurfacesRateLimitError() async {
    let session = makeSession(
      statusCode: 429,
      data: Data(#"{"error":"rate_limited"}"#.utf8)
    )
    let client = LarkSlotClient(
      baseURL: URL(string: "https://l.garyyang.work")!,
      session: session
    )

    do {
      try await client.updateSlot(
        credential: "cred-123",
        slotID: "slot-abc",
        value: "hello"
      )
      XCTFail("Expected request to fail")
    } catch let error as LarkSlotSyncError {
      XCTAssertEqual(error.errorDescription, "写入过于频繁，请稍后再试 (429)")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makeSnapshot() -> TokenCostSnapshot {
    TokenCostSnapshot(
      todayTokens: 149_736_619,
      todayCostUSD: 51.89210695,
      last7DaysTokens: 1_234_567_890,
      last7DaysCostUSD: 412.34,
      last30DaysTokens: 8_103_521_272,
      last30DaysCostUSD: 3209.99094295,
      modelSummaries: [
        TokenCostModelSummary(
          modelName: "gpt-5.4",
          inputTokens: 0,
          cacheReadTokens: 0,
          outputTokens: 0,
          totalTokens: 8_103_521_272,
          costUSD: 3209.99094295,
          costShare: 0.99,
          tokenShare: 0.99
        )
      ],
      daily: [],
      source: TokenCostSourceSummary(
        mode: .iCloudMerged,
        syncedDeviceCount: 2,
        localDeviceID: "device-1",
        localDeviceName: "This Mac",
        updatedAt: Self.updatedAt
      ),
      localSummary: TokenCostLocalSummary(
        todayTokens: 12_345_678,
        todayCostUSD: 4.56,
        last7DaysTokens: 98_765_432,
        last7DaysCostUSD: 33.21,
        last30DaysTokens: 456_789_012,
        last30DaysCostUSD: 123.45
      ),
      updatedAt: Self.updatedAt
    )
  }

  private func makeSession(
    statusCode: Int,
    data: Data,
    assertRequest: ((URLRequest) throws -> Void)? = nil
  ) -> URLSession {
    LarkSlotURLProtocol.responseStatusCode = statusCode
    LarkSlotURLProtocol.responseData = data
    LarkSlotURLProtocol.assertRequest = assertRequest

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LarkSlotURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  private static let updatedAt = ISO8601DateFormatter().date(from: "2026-04-14T16:08:00+08:00")!
  private static let shanghaiTimeZone = TimeZone(identifier: "Asia/Shanghai")!

  private static func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
      return body
    }

    guard let stream = request.httpBodyStream else {
      return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: bufferSize)
      if read < 0 {
        return nil
      }
      if read == 0 {
        break
      }
      data.append(buffer, count: read)
    }
    return data
  }
}

private final class LarkSlotURLProtocol: URLProtocol {
  nonisolated(unsafe) static var responseStatusCode = 200
  nonisolated(unsafe) static var responseData = Data()
  nonisolated(unsafe) static var assertRequest: ((URLRequest) throws -> Void)?

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    do {
      try Self.assertRequest?(request)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
      return
    }

    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "https://example.com")!,
      statusCode: Self.responseStatusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.responseData)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
