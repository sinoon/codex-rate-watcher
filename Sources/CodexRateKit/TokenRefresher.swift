import Foundation

/// Refreshes ChatGPT OAuth tokens using the refresh_token grant.
///
/// Mirrors the Codex CLI behaviour in `codex-rs/login/src/auth/manager.rs`.
public struct TokenRefresher: Sendable {

  public init() {}

  // Same issuer / clientID used by DeviceCodeAuth and Codex CLI.
  private static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
  private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

  public enum RefreshError: LocalizedError {
    case noRefreshToken
    case networkError(String)
    case permanentFailure(String)   // 401 → must re-login
    case serverError(Int, String)   // transient

    public var errorDescription: String? {
      switch self {
      case .noRefreshToken:
        return "auth.json 中没有 refresh_token，请重新登录。"
      case .networkError(let msg):
        return "刷新 token 时网络错误：\(msg)"
      case .permanentFailure(let msg):
        return "refresh_token 已失效，请重新登录：\(msg)"
      case .serverError(let code, let msg):
        return "刷新 token 服务端错误 (\(code))：\(msg)"
      }
    }

    public var isPermanent: Bool {
      switch self {
      case .permanentFailure, .noRefreshToken: return true
      default: return false
      }
    }
  }

  // MARK: - Response

  private struct RefreshResponse: Decodable {
    let id_token: String?
    let access_token: String?
    let refresh_token: String?
  }

  // MARK: - Public

  /// Attempt to refresh tokens.  On success, returns updated raw auth.json
  /// `Data` ready to be written back via `AuthStore.writeRawData(_:)`.
  public func refresh(currentAuthData: Data) async throws -> Data {
    // 1. Parse existing auth.json to get the refresh_token.
    guard let json = try? JSONSerialization.jsonObject(with: currentAuthData) as? [String: Any],
          let tokens = json["tokens"] as? [String: Any],
          let refreshToken = tokens["refresh_token"] as? String,
          !refreshToken.isEmpty else {
      throw RefreshError.noRefreshToken
    }

    // 2. POST to token endpoint.
    let body: [String: String] = [
      "client_id": Self.clientID,
      "grant_type": "refresh_token",
      "refresh_token": refreshToken,
    ]

    var request = URLRequest(url: Self.tokenURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw RefreshError.networkError("非 HTTP 响应")
    }

    // 3. Handle errors.
    if http.statusCode == 401 {
      let msg = String(data: data, encoding: .utf8) ?? ""
      throw RefreshError.permanentFailure(msg)
    }

    guard (200..<300).contains(http.statusCode) else {
      let msg = String(data: data, encoding: .utf8) ?? ""
      throw RefreshError.serverError(http.statusCode, msg)
    }

    let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)

    // 4. Merge new tokens into the existing auth.json.
    var mutableJSON = json
    var mutableTokens = tokens

    if let newAccess = refreshResponse.access_token, !newAccess.isEmpty {
      mutableTokens["access_token"] = newAccess
    }
    if let newID = refreshResponse.id_token, !newID.isEmpty {
      mutableTokens["id_token"] = newID
    }
    if let newRefresh = refreshResponse.refresh_token, !newRefresh.isEmpty {
      mutableTokens["refresh_token"] = newRefresh
    }

    mutableJSON["tokens"] = mutableTokens

    // Update last_refresh timestamp (ISO 8601, matching Codex CLI format).
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    mutableJSON["last_refresh"] = formatter.string(from: Date())

    return try JSONSerialization.data(withJSONObject: mutableJSON, options: [.prettyPrinted, .sortedKeys])
  }
}
