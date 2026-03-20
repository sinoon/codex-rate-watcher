import CryptoKit
import Foundation

public struct AuthSnapshot: Sendable {
  public let accessToken: String
  public let accountID: String?
  public let authMode: String?
  public let email: String?
}

public struct AuthEnvelope: Sendable {
  public let rawData: Data
  public let snapshot: AuthSnapshot
  public let fingerprint: String
}

public enum AuthStoreError: LocalizedError {
  case missingToken
  case invalidJWT

  public var errorDescription: String? {
    switch self {
    case .missingToken:
      return "我在 ~/.codex/auth.json 里没有找到可用的 access token。"
    case .invalidJWT:
      return "Access token 格式无效。"
    }
  }
}

public struct AuthStore: @unchecked Sendable {
  private struct Payload: Decodable {
    struct Tokens: Decodable {
      let accessToken: String?
      let accountID: String?

      enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
      }
    }

    let authMode: String?
    let tokens: Tokens

    enum CodingKeys: String, CodingKey {
      case authMode = "auth_mode"
      case tokens
    }
  }

  private let fileURL: URL
  private let decoder = JSONDecoder()

  public init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")) {
    self.fileURL = fileURL
  }

  public var watchedDirectoryURL: URL {
    fileURL.deletingLastPathComponent()
  }

  public func load() throws -> AuthSnapshot {
    try loadEnvelope().snapshot
  }

  public func loadEnvelope() throws -> AuthEnvelope {
    let data = try loadRawData()
    return try envelope(from: data)
  }

  public func loadRawData() throws -> Data {
    try Data(contentsOf: fileURL)
  }

  public func envelope(from data: Data) throws -> AuthEnvelope {
    let payload = try decoder.decode(Payload.self, from: data)
    guard let accessToken = payload.tokens.accessToken, !accessToken.isEmpty else {
      throw AuthStoreError.missingToken
    }

    // Parse email from JWT access token
    let email = Self.extractEmail(from: accessToken)

    return AuthEnvelope(
      rawData: data,
      snapshot: AuthSnapshot(
        accessToken: accessToken,
        accountID: payload.tokens.accountID,
        authMode: payload.authMode,
        email: email
      ),
      fingerprint: fingerprint(for: data)
    )
  }

  public func writeRawData(_ data: Data) throws {
    try data.write(to: fileURL, options: .atomic)
  }

  private func fingerprint(for data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
  }

  // MARK: - JWT Parsing

  /// Extract email from JWT access token (if exists)
  private static func extractEmail(from jwt: String) -> String? {
    let parts = jwt.split(separator: ".")
    guard parts.count >= 2 else { return nil }

    var payload = String(parts[1])
    // Fix base64 padding
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

    guard let payloadData = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
      return nil
    }

    do {
      let json = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
      if let profile = json?["https://api.openai.com/profile"] as? [String: Any] {
        return profile["email"] as? String
      }
    } catch { }

    return nil
  }
}
