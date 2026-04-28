import XCTest
@testable import CodexRateKit

final class RateWatcherURLSessionFactoryTests: XCTestCase {
  func testDefaultConfigurationAvoidsSharedCacheAndCookies() {
    let configuration = RateWatcherURLSessionFactory.makeConfiguration()

    XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertNil(configuration.urlCache)
    XCTAssertEqual(configuration.timeoutIntervalForRequest, 30)
    XCTAssertEqual(configuration.timeoutIntervalForResource, 60)
    XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 4)
    XCTAssertFalse(configuration.waitsForConnectivity)
    XCTAssertFalse(configuration.httpShouldSetCookies)
    XCTAssertNil(configuration.httpCookieStorage)
    XCTAssertEqual(configuration.httpAdditionalHeaders?["Cache-Control"] as? String, "no-store")
  }
}
