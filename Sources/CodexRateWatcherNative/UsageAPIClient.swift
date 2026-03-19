import Foundation

enum UsageAPIError: LocalizedError {
  case invalidResponse
  case httpError(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "额度接口返回的数据格式不对。"
    case .httpError(let statusCode, let message):
      let summary = Self.friendlyMessage(statusCode: statusCode, raw: message)
      return summary
    }
  }

  /// Parse raw response body into a short, human-readable error string.
  private static func friendlyMessage(statusCode: Int, raw: String) -> String {
    // Try to extract "detail" from JSON like {"detail":"Payment required"}
    if let data = raw.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let detail = json["detail"] as? String, !detail.isEmpty {
      let shortDetail = detail.count > 60 ? String(detail.prefix(60)) + "…" : detail
      return "接口 \(statusCode)：\(shortDetail)"
    }

    // Common status code descriptions
    switch statusCode {
    case 401:
      return "认证已过期，请重新登录 (401)"
    case 402:
      return "订阅已过期或付费状态异常 (402)"
    case 403:
      return "无权访问此账号 (403)"
    case 429:
      return "请求过于频繁，稍后重试 (429)"
    case 500...599:
      return "服务端错误，稍后重试 (\(statusCode))"
    default:
      if raw.isEmpty {
        return "请求失败 (\(statusCode))"
      }
      let short = raw.count > 60 ? String(raw.prefix(60)) + "…" : raw
      return "请求失败 (\(statusCode))：\(short)"
    }
  }
}

struct UsageAPIClient {
  private let session: URLSession
  private let decoder = JSONDecoder()
  private let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetchUsage(auth: AuthSnapshot) async throws -> UsageSnapshot {
    var request = URLRequest(url: endpoint)
    request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("codex-rate-watcher-native/0.1", forHTTPHeaderField: "User-Agent")
    if let accountID = auth.accountID, !accountID.isEmpty {
      request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
    }

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw UsageAPIError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw UsageAPIError.httpError(statusCode: httpResponse.statusCode, message: message)
    }

    return try decoder.decode(UsageSnapshot.self, from: data)
  }
}
