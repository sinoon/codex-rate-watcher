import CryptoKit
import Foundation

struct AuthSnapshot {
  let accessToken: String
  let accountID: String?
  let authMode: String?
}

struct AuthEnvelope {
  let rawData: Data
  let snapshot: AuthSnapshot
  let fingerprint: String
}

enum AuthStoreError: LocalizedError {
  case missingToken

  var errorDescription: String? {
    switch self {
    case .missingToken:
      return "我在 ~/.codex/auth.json 里没有找到可用的 access token。"
    }
  }
}

struct AuthStore {
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

  init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")) {
    self.fileURL = fileURL
  }

  var watchedDirectoryURL: URL {
    fileURL.deletingLastPathComponent()
  }

  func load() throws -> AuthSnapshot {
    try loadEnvelope().snapshot
  }

  func loadEnvelope() throws -> AuthEnvelope {
    let data = try loadRawData()
    return try envelope(from: data)
  }

  func loadRawData() throws -> Data {
    try Data(contentsOf: fileURL)
  }

  func envelope(from data: Data) throws -> AuthEnvelope {
    let payload = try decoder.decode(Payload.self, from: data)
    guard let accessToken = payload.tokens.accessToken, !accessToken.isEmpty else {
      throw AuthStoreError.missingToken
    }
    return AuthEnvelope(
      rawData: data,
      snapshot: AuthSnapshot(
        accessToken: accessToken,
        accountID: payload.tokens.accountID,
        authMode: payload.authMode
      ),
      fingerprint: fingerprint(for: data)
    )
  }

  func writeRawData(_ data: Data) throws {
    try data.write(to: fileURL, options: .atomic)
  }

  private func fingerprint(for data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
  }
}
