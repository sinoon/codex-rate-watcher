import XCTest
@testable import CodexRateKit

final class LarkSignatureAutoSyncTests: XCTestCase {

  func testStoreRoundTripsConfig() async {
    let fileURL = makeTempFileURL()
    let store = LarkSignatureAutoSyncStore(fileURL: fileURL)
    let config = LarkSignatureAutoSyncConfig(
      enabled: true,
      credential: "cred-123",
      slotID: "slot-abc",
      label: "",
      baseURL: "https://l.garyyang.work",
      useLocalSummary: false,
      lastSyncedValue: "今日 1.0K tok $1.00 · 12:00",
      lastSyncedAt: Self.baseDate
    )

    await store.save(config)
    let loaded = await store.load()

    XCTAssertEqual(loaded, config)
  }

  func testServiceSkipsPushWhenValueIsUnchanged() async throws {
    let store = LarkSignatureAutoSyncStore(fileURL: makeTempFileURL())
    await store.save(
      LarkSignatureAutoSyncConfig(
        enabled: true,
        credential: "cred-123",
        slotID: "slot-abc",
        label: "",
        baseURL: "https://l.garyyang.work",
        useLocalSummary: false
      )
    )

    let session = makeSession(statusCode: 200, data: Data(#"{"success":true}"#.utf8))
    let service = LarkSignatureAutoSyncService(
      store: store,
      clientFactory: { baseURL in
        LarkSlotClient(baseURL: baseURL, session: session)
      }
    )
    let snapshot = makeSnapshot(todayTokens: 149_736_619, updatedAt: Self.baseDate)

    await service.syncIfNeeded(snapshot: snapshot, now: Self.baseDate)
    await service.syncIfNeeded(snapshot: snapshot, now: Self.baseDate.addingTimeInterval(120))

    XCTAssertEqual(LarkAutoSyncURLProtocol.requestCount, 1)
    let saved = await store.load()
    XCTAssertEqual(
      saved.lastSyncedValue,
      "Token 今日149.7M/$52 · 7天1.2B/$412 · 30天8.1B/$3.2k"
    )
  }

  func testServiceThrottlesChangedValueInsideOneMinuteWindow() async throws {
    let store = LarkSignatureAutoSyncStore(fileURL: makeTempFileURL())
    await store.save(
      LarkSignatureAutoSyncConfig(
        enabled: true,
        credential: "cred-123",
        slotID: "slot-abc",
        label: "",
        baseURL: "https://l.garyyang.work",
        useLocalSummary: false
      )
    )

    let session = makeSession(statusCode: 200, data: Data(#"{"success":true}"#.utf8))
    let service = LarkSignatureAutoSyncService(
      store: store,
      clientFactory: { baseURL in
        LarkSlotClient(baseURL: baseURL, session: session)
      }
    )

    await service.syncIfNeeded(snapshot: makeSnapshot(todayTokens: 149_736_619, updatedAt: Self.baseDate), now: Self.baseDate)
    await service.syncIfNeeded(
      snapshot: makeSnapshot(todayTokens: 150_000_000, updatedAt: Self.baseDate.addingTimeInterval(30)),
      now: Self.baseDate.addingTimeInterval(30)
    )

    XCTAssertEqual(LarkAutoSyncURLProtocol.requestCount, 1)
    let saved = await store.load()
    XCTAssertEqual(
      saved.lastSyncedValue,
      "Token 今日149.7M/$52 · 7天1.2B/$412 · 30天8.1B/$3.2k"
    )
  }

  func testServicePushesChangedValueAfterThrottleWindow() async throws {
    let store = LarkSignatureAutoSyncStore(fileURL: makeTempFileURL())
    await store.save(
      LarkSignatureAutoSyncConfig(
        enabled: true,
        credential: "cred-123",
        slotID: "slot-abc",
        label: "",
        baseURL: "https://l.garyyang.work",
        useLocalSummary: false
      )
    )

    let session = makeSession(statusCode: 200, data: Data(#"{"success":true}"#.utf8))
    let service = LarkSignatureAutoSyncService(
      store: store,
      clientFactory: { baseURL in
        LarkSlotClient(baseURL: baseURL, session: session)
      }
    )

    await service.syncIfNeeded(snapshot: makeSnapshot(todayTokens: 149_736_619, updatedAt: Self.baseDate), now: Self.baseDate)
    await service.syncIfNeeded(
      snapshot: makeSnapshot(todayTokens: 180_000_000, updatedAt: Self.baseDate.addingTimeInterval(65)),
      now: Self.baseDate.addingTimeInterval(65)
    )

    XCTAssertEqual(LarkAutoSyncURLProtocol.requestCount, 2)
    let saved = await store.load()
    XCTAssertEqual(
      saved.lastSyncedValue,
      "Token 今日180.0M/$52 · 7天1.2B/$412 · 30天8.1B/$3.2k"
    )
  }

  private func makeSession(statusCode: Int, data: Data) -> URLSession {
    LarkAutoSyncURLProtocol.responseStatusCode = statusCode
    LarkAutoSyncURLProtocol.responseData = data
    LarkAutoSyncURLProtocol.requestCount = 0

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LarkAutoSyncURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  private func makeSnapshot(todayTokens: Int, updatedAt: Date) -> TokenCostSnapshot {
    TokenCostSnapshot(
      todayTokens: todayTokens,
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
      updatedAt: updatedAt
    )
  }

  private func makeTempFileURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "LarkSignatureAutoSyncTests-\(UUID().uuidString).json")
  }

  private static let baseDate = ISO8601DateFormatter().date(from: "2026-04-14T16:08:00+08:00")!
}

private final class LarkAutoSyncURLProtocol: URLProtocol {
  nonisolated(unsafe) static var responseStatusCode = 200
  nonisolated(unsafe) static var responseData = Data()
  nonisolated(unsafe) static var requestCount = 0

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.requestCount += 1
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
