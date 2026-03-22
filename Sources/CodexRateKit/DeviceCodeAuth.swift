import Foundation

// MARK: - Device Code Authentication

/// Implements the OAuth 2.0 Device Authorization Grant flow
/// used by Codex CLI to authenticate with OpenAI.
public struct DeviceCodeAuth: Sendable {

  // MARK: - Constants

  private static let issuer = "https://auth.openai.com"
  private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
  private static let redirectURI = "\(issuer)/deviceauth/callback"
  private static let maxPollDuration: TimeInterval = 15 * 60 // 15 minutes

  /// The URL the user must visit to enter the device code.
  public static let verificationURL = "\(issuer)/codex/device"

  // MARK: - Response Models

  public struct DeviceCodeResponse: Sendable {
    public let deviceAuthID: String
    public let userCode: String
    public let interval: Int
  }

  public struct AuthTokens: Sendable {
    public let idToken: String
    public let accessToken: String
    public let refreshToken: String
    public let accountID: String
  }

  // MARK: - Errors

  public enum AuthError: LocalizedError {
    case networkError(String)
    case invalidResponse(Int)
    case timeout
    case cancelled
    case missingField(String)
    case tokenExchangeFailed(String)

    public var errorDescription: String? {
      switch self {
      case .networkError(let msg): return "网络错误：\(msg)"
      case .invalidResponse(let code): return "服务器返回错误 (HTTP \(code))"
      case .timeout: return "登录超时（15 分钟），请重试"
      case .cancelled: return "登录已取消"
      case .missingField(let field): return "返回数据缺少必要字段：\(field)"
      case .tokenExchangeFailed(let msg): return "Token 交换失败：\(msg)"
      }
    }
  }

  // MARK: - Internal JSON Models

  private struct UserCodeRequest: Encodable {
    let client_id: String
  }

  private struct UserCodeResponseJSON: Decodable {
    let device_auth_id: String
    let user_code: String
    let interval: Int
  }

  private struct TokenPollRequest: Encodable {
    let device_auth_id: String
    let user_code: String
  }

  private struct TokenPollResponseJSON: Decodable {
    let authorization_code: String?
    let code_challenge: String?
    let code_verifier: String?
  }

  private struct TokenExchangeResponseJSON: Decodable {
    let id_token: String?
    let access_token: String?
    let refresh_token: String?
  }

  // MARK: - Public API

  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  /// Step 1: Request a device code from OpenAI.
  public func requestDeviceCode() async throws -> DeviceCodeResponse {
    let url = URL(string: "\(Self.issuer)/api/accounts/deviceauth/usercode")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = UserCodeRequest(client_id: Self.clientID)
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw AuthError.networkError("非 HTTP 响应")
    }
    guard http.statusCode == 200 else {
      _ = String(data: data, encoding: .utf8)
      throw AuthError.invalidResponse(http.statusCode)
    }

    let json = try JSONDecoder().decode(UserCodeResponseJSON.self, from: data)
    return DeviceCodeResponse(
      deviceAuthID: json.device_auth_id,
      userCode: json.user_code,
      interval: json.interval
    )
  }

  /// Steps 2 & 3: Poll for an authorization code, then exchange it for
  /// access / refresh / id tokens.
  ///
  /// - Parameters:
  ///   - deviceAuthID: The `device_auth_id` returned by `requestDeviceCode()`.
  ///   - userCode: The `user_code` the user enters in the browser.
  ///   - interval: Polling interval in seconds.
  /// - Returns: Final `AuthTokens` ready to be persisted.
  public func pollAndExchange(
    deviceAuthID: String,
    userCode: String,
    interval: Int
  ) async throws -> AuthTokens {
    // Step 2: Poll for authorization code
    let pollResult = try await pollForAuthorizationCode(
      deviceAuthID: deviceAuthID,
      userCode: userCode,
      interval: interval
    )

    // Step 3: Exchange authorization code for tokens
    return try await exchangeCodeForTokens(
      authorizationCode: pollResult.authorizationCode,
      codeVerifier: pollResult.codeVerifier
    )
  }

  /// Build a `Data` blob matching `~/.codex/auth.json` format.
  public static func buildAuthJSON(tokens: AuthTokens) throws -> Data {
    // Use ISO 8601 with fractional seconds to match Codex CLI format
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let authDict: [String: Any] = [
      "auth_mode": "chatgpt",
      "OPENAI_API_KEY": NSNull(),
      "tokens": [
        "id_token": tokens.idToken,
        "access_token": tokens.accessToken,
        "refresh_token": tokens.refreshToken,
        "account_id": tokens.accountID,
      ] as [String: Any],
      "last_refresh": formatter.string(from: Date()),
    ]

    return try JSONSerialization.data(
      withJSONObject: authDict,
      options: [.prettyPrinted, .sortedKeys]
    )
  }

  // MARK: - Internal Steps

  private struct PollResult {
    let authorizationCode: String
    let codeVerifier: String
  }

  private func pollForAuthorizationCode(
    deviceAuthID: String,
    userCode: String,
    interval: Int
  ) async throws -> PollResult {
    let url = URL(string: "\(Self.issuer)/api/accounts/deviceauth/token")!
    let pollInterval = max(interval, 2)
    let deadline = Date().addingTimeInterval(Self.maxPollDuration)

    while Date() < deadline {
      try Task.checkCancellation()

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body = TokenPollRequest(
        device_auth_id: deviceAuthID,
        user_code: userCode
      )
      request.httpBody = try JSONEncoder().encode(body)

      do {
        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
          let json = try JSONDecoder().decode(
            TokenPollResponseJSON.self, from: data
          )
          if let authCode = json.authorization_code,
             let verifier = json.code_verifier
          {
            return PollResult(
              authorizationCode: authCode,
              codeVerifier: verifier
            )
          }
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // Network glitch — keep polling
      }

      try await Task.sleep(for: .seconds(pollInterval))
    }

    throw AuthError.timeout
  }

  private func exchangeCodeForTokens(
    authorizationCode: String,
    codeVerifier: String
  ) async throws -> AuthTokens {
    let url = URL(string: "\(Self.issuer)/oauth/token")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(
      "application/x-www-form-urlencoded",
      forHTTPHeaderField: "Content-Type"
    )

    let params: [(String, String)] = [
      ("grant_type", "authorization_code"),
      ("code", authorizationCode),
      ("code_verifier", codeVerifier),
      ("redirect_uri", Self.redirectURI),
      ("client_id", Self.clientID),
    ]

    request.httpBody = params
      .map { key, value in
        let v = value.addingPercentEncoding(
          withAllowedCharacters: .urlQueryAllowed
        ) ?? value
        return "\(key)=\(v)"
      }
      .joined(separator: "&")
      .data(using: .utf8)

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw AuthError.networkError("非 HTTP 响应")
    }
    guard http.statusCode == 200 else {
      let body = String(data: data, encoding: .utf8) ?? "unknown"
      throw AuthError.tokenExchangeFailed("HTTP \(http.statusCode): \(body)")
    }

    let tokenResponse = try JSONDecoder().decode(
      TokenExchangeResponseJSON.self, from: data
    )

    guard let idToken = tokenResponse.id_token else {
      throw AuthError.missingField("id_token")
    }
    guard let accessToken = tokenResponse.access_token else {
      throw AuthError.missingField("access_token")
    }
    guard let refreshToken = tokenResponse.refresh_token else {
      throw AuthError.missingField("refresh_token")
    }

    let accountID = try Self.extractAccountID(from: idToken)

    return AuthTokens(
      idToken: idToken,
      accessToken: accessToken,
      refreshToken: refreshToken,
      accountID: accountID
    )
  }

  // MARK: - JWT Helpers

  /// Extract `account_id` from the `id_token` JWT.
  /// Path: `https://api.openai.com/auth` → `user_id`, fallback to `sub`.
  private static func extractAccountID(from jwt: String) throws -> String {
    let parts = jwt.split(separator: ".")
    guard parts.count >= 2 else {
      throw AuthError.missingField("account_id (invalid JWT)")
    }

    var payload = String(parts[1])
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

    guard let payloadData = Data(
      base64Encoded: payload, options: .ignoreUnknownCharacters
    ) else {
      throw AuthError.missingField("account_id (base64 decode)")
    }

    guard let json = try JSONSerialization.jsonObject(with: payloadData)
      as? [String: Any]
    else {
      throw AuthError.missingField("account_id (JSON parse)")
    }

    if let auth = json["https://api.openai.com/auth"] as? [String: Any],
       let userID = auth["user_id"] as? String
    {
      return userID
    }

    if let sub = json["sub"] as? String {
      return sub
    }

    throw AuthError.missingField("account_id")
  }
}
