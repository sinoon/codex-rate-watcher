import XCTest
@testable import CodexRateKit

final class UsageSampleTests: XCTestCase {

  func testRoundTrip() throws {
    let sample = UsageSample(
      capturedAt: Date(timeIntervalSince1970: 1773970000),
      primaryUsedPercent: 42.5,
      primaryResetAt: 1773980000,
      secondaryUsedPercent: 10.0,
      secondaryResetAt: 1774400000,
      reviewUsedPercent: 5.0,
      reviewResetAt: 1773990000
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(sample)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(UsageSample.self, from: data)

    XCTAssertEqual(
      decoded.capturedAt.timeIntervalSince1970,
      sample.capturedAt.timeIntervalSince1970,
      accuracy: 0.001
    )
    XCTAssertEqual(decoded.primaryUsedPercent, 42.5, accuracy: 0.001)
    XCTAssertEqual(decoded.primaryResetAt, 1773980000, accuracy: 0.1)
    XCTAssertEqual(decoded.secondaryUsedPercent, 10.0)
    XCTAssertEqual(decoded.secondaryResetAt, 1774400000)
    XCTAssertEqual(decoded.reviewUsedPercent, 5.0, accuracy: 0.001)
    XCTAssertEqual(decoded.reviewResetAt, 1773990000, accuracy: 0.1)
  }

  func testRoundTripWithNilSecondary() throws {
    let sample = UsageSample(
      capturedAt: Date(timeIntervalSince1970: 1773970000),
      primaryUsedPercent: 42.5,
      primaryResetAt: 1773980000,
      secondaryUsedPercent: nil,
      secondaryResetAt: nil,
      reviewUsedPercent: 5.0,
      reviewResetAt: 1773990000
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(sample)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(UsageSample.self, from: data)

    XCTAssertEqual(decoded.primaryUsedPercent, 42.5, accuracy: 0.001)
    XCTAssertNil(decoded.secondaryUsedPercent)
    XCTAssertNil(decoded.secondaryResetAt)
    XCTAssertEqual(decoded.reviewUsedPercent, 5.0, accuracy: 0.001)
  }

  func testInitWithDefaults() {
    let now = Date()
    let sample = UsageSample(
      capturedAt: now,
      primaryUsedPercent: 50.0,
      primaryResetAt: 1773980000,
      reviewUsedPercent: 0.0,
      reviewResetAt: 1773990000
    )

    XCTAssertEqual(sample.primaryUsedPercent, 50.0)
    XCTAssertNil(sample.secondaryUsedPercent)
    XCTAssertNil(sample.secondaryResetAt)
    XCTAssertEqual(sample.reviewUsedPercent, 0.0)
  }

  func testDecodingFromExternalJSON() throws {
    // Simulate a JSON that might be stored on disk
    let json = """
    {
      "capturedAt": 704505600.0,
      "primaryUsedPercent": 75.5,
      "primaryResetAt": 1773980000,
      "secondaryUsedPercent": 25.0,
      "secondaryResetAt": 1774400000,
      "reviewUsedPercent": 3.0,
      "reviewResetAt": 1773990000
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(UsageSample.self, from: json)
    XCTAssertEqual(decoded.primaryUsedPercent, 75.5, accuracy: 0.001)
    XCTAssertEqual(decoded.secondaryUsedPercent, 25.0)
    XCTAssertEqual(decoded.reviewUsedPercent, 3.0, accuracy: 0.001)
  }

  func testDecodingRepairsImplausibleFarFutureResetTimes() throws {
    let json = """
    {
      "capturedAt": 704505600.0,
      "primaryUsedPercent": 75.5,
      "primaryResetAt": 4102444800,
      "secondaryUsedPercent": 25.0,
      "secondaryResetAt": 4102444800,
      "reviewUsedPercent": 3.0,
      "reviewResetAt": 4102444800
    }
    """.data(using: .utf8)!

    let before = Date().timeIntervalSince1970
    let decoded = try JSONDecoder().decode(UsageSample.self, from: json)
    let after = Date().timeIntervalSince1970

    XCTAssertGreaterThanOrEqual(decoded.primaryResetAt, before + 17_990)
    XCTAssertLessThanOrEqual(decoded.primaryResetAt, after + 18_010)

    let secondaryResetAt = try XCTUnwrap(decoded.secondaryResetAt)
    XCTAssertGreaterThanOrEqual(secondaryResetAt, before + 604_790)
    XCTAssertLessThanOrEqual(secondaryResetAt, after + 604_810)

    XCTAssertGreaterThanOrEqual(decoded.reviewResetAt, before + 17_990)
    XCTAssertLessThanOrEqual(decoded.reviewResetAt, after + 18_010)
  }

  func testEncodingProducesAllKeys() throws {
    let sample = UsageSample(
      capturedAt: Date(timeIntervalSince1970: 1000000),
      primaryUsedPercent: 42.5,
      primaryResetAt: 2000000,
      secondaryUsedPercent: 10.0,
      secondaryResetAt: 3000000,
      reviewUsedPercent: 5.0,
      reviewResetAt: 4000000
    )

    let data = try JSONEncoder().encode(sample)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    XCTAssertNotNil(dict["capturedAt"])
    XCTAssertNotNil(dict["primaryUsedPercent"])
    XCTAssertNotNil(dict["primaryResetAt"])
    XCTAssertNotNil(dict["secondaryUsedPercent"])
    XCTAssertNotNil(dict["secondaryResetAt"])
    XCTAssertNotNil(dict["reviewUsedPercent"])
    XCTAssertNotNil(dict["reviewResetAt"])
  }

  func testEncodingOmitsNilSecondary() throws {
    let sample = UsageSample(
      capturedAt: Date(timeIntervalSince1970: 1000000),
      primaryUsedPercent: 42.5,
      primaryResetAt: 2000000,
      reviewUsedPercent: 5.0,
      reviewResetAt: 4000000
    )

    let data = try JSONEncoder().encode(sample)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    XCTAssertNotNil(dict["primaryUsedPercent"])
    // With default Codable synthesis, nil optionals are omitted
    // This verifies the round-trip still works correctly
    let decoded = try JSONDecoder().decode(UsageSample.self, from: data)
    XCTAssertNil(decoded.secondaryUsedPercent)
    XCTAssertNil(decoded.secondaryResetAt)
  }

  func testMultipleSamplesArrayRoundTrip() throws {
    let samples = [
      UsageSample(
        capturedAt: Date(timeIntervalSince1970: 1000000),
        primaryUsedPercent: 10.0,
        primaryResetAt: 2000000,
        secondaryUsedPercent: 5.0,
        secondaryResetAt: 3000000,
        reviewUsedPercent: 1.0,
        reviewResetAt: 4000000
      ),
      UsageSample(
        capturedAt: Date(timeIntervalSince1970: 1001000),
        primaryUsedPercent: 20.0,
        primaryResetAt: 2000000,
        reviewUsedPercent: 2.0,
        reviewResetAt: 4000000
      ),
    ]

    let data = try JSONEncoder().encode(samples)
    let decoded = try JSONDecoder().decode([UsageSample].self, from: data)

    XCTAssertEqual(decoded.count, 2)
    XCTAssertEqual(decoded[0].primaryUsedPercent, 10.0)
    XCTAssertEqual(decoded[1].primaryUsedPercent, 20.0)
    XCTAssertNotNil(decoded[0].secondaryUsedPercent)
    XCTAssertNil(decoded[1].secondaryUsedPercent)
  }
}
