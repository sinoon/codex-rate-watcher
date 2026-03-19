import Foundation

enum UsageAPIError: LocalizedError {
  case invalidResponse
  case httpError(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Usage API returned an invalid response."
    case .httpError(let statusCode, let message):
      if message.isEmpty {
        return "Usage API request failed with status \(statusCode)."
      }
      return "Usage API request failed with status \(statusCode): \(message)"
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
