import Foundation

// MARK: - Types

public enum ProxyError: LocalizedError {
  case socketCreation
  case bindFailed(port: UInt16)
  case listenFailed

  public var errorDescription: String? {
    switch self {
    case .socketCreation: return "Failed to create server socket"
    case .bindFailed(let port): return "Port \(port) already in use \u{2014} try --port <other>"
    case .listenFailed: return "Failed to listen on socket"
    }
  }
}

private struct HTTPReq: Sendable {
  let method: String
  let path: String
  let headers: [(String, String)]
  let body: Data
}

// MARK: - ProxyServer

public final class ProxyServer: @unchecked Sendable {

  public struct Config: Sendable {
    public let port: UInt16
    public let upstream: String
    public let autoRelay: Bool
    public let verbose: Bool

    public init(
      port: UInt16 = 19876,
      upstream: String = "https://api.openai.com",
      autoRelay: Bool = true,
      verbose: Bool = false
    ) {
      self.port = port
      self.upstream = upstream
      self.autoRelay = autoRelay
      self.verbose = verbose
    }
  }

  private let config: Config
  private let upstreamURL: URL
  private let session: URLSession
  private let lock = NSLock()
  private var requestCount = 0
  private var failoverCount = 0
  private var errorCount = 0

  public struct Stats: Sendable {
    public let requests: Int
    public let failovers: Int
    public let errors: Int
  }

  public var stats: Stats {
    lock.withLock { Stats(requests: requestCount, failovers: failoverCount, errors: errorCount) }
  }

  private var _isRunning = false
  public var isRunning: Bool { lock.withLock { _isRunning } }

  public init(config: Config, session: URLSession = RateWatcherURLSessionFactory.shared) {
    self.config = config
    self.session = session
    self.upstreamURL = URL(string: config.upstream)!
  }

  // MARK: - Run

  public func run() async throws {
    let serverFD = socket(AF_INET, SOCK_STREAM, 0)
    guard serverFD >= 0 else { throw ProxyError.socketCreation }

    var opt: Int32 = 1
    setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = config.port.bigEndian
    addr.sin_addr = in_addr(s_addr: UInt32(0x7f000001).bigEndian)

    let bindOK = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindOK == 0 else {
      Darwin.close(serverFD)
      throw ProxyError.bindFailed(port: config.port)
    }
    guard Darwin.listen(serverFD, 128) == 0 else {
      Darwin.close(serverFD)
      throw ProxyError.listenFailed
    }

    // Non-blocking for async accept loop
    let flags = fcntl(serverFD, F_GETFL)
    _ = fcntl(serverFD, F_SETFL, flags | O_NONBLOCK)

    printBanner()
    lock.withLock { _isRunning = true }

    while !Task.isCancelled {
      var caddr = sockaddr_in()
      var clen = socklen_t(MemoryLayout<sockaddr_in>.size)
      let cfd = withUnsafeMutablePointer(to: &caddr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.accept(serverFD, $0, &clen)
        }
      }

      if cfd < 0 {
        if errno == EAGAIN || errno == EWOULDBLOCK {
          try await Task.sleep(for: .milliseconds(20))
          continue
        }
        break
      }

      // Client socket timeouts
      var tv = timeval(tv_sec: 30, tv_usec: 0)
      setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
      setsockopt(cfd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

      let clientFD = cfd
      Task.detached { [self] in
        await self.handleClient(fd: clientFD)
        Darwin.close(clientFD)
      }
    }

    lock.withLock { _isRunning = false }
    Darwin.close(serverFD)
  }

  // MARK: - Client Handling

  private func handleClient(fd: Int32) async {
    guard let req = readHTTP(fd: fd) else { return }
    lock.withLock { requestCount += 1 }

    // Health check
    if req.method == "GET" && (req.path == "/" || req.path == "/health") {
      let s = lock.withLock { (r: requestCount, f: failoverCount, e: errorCount) }
      let json = #"{"status":"ok","requests":\#(s.r),"failovers":\#(s.f),"errors":\#(s.e),"upstream":"\#(config.upstream)"}"#
      writeResp(fd: fd, status: 200, text: "OK",
                headers: [("Content-Type", "application/json")], body: Data(json.utf8))
      return
    }

    // CORS preflight
    if req.method == "OPTIONS" {
      writeResp(fd: fd, status: 204, text: "No Content", headers: [
        ("Access-Control-Allow-Origin", "*"),
        ("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS"),
        ("Access-Control-Allow-Headers", "Authorization, Content-Type, OpenAI-Organization"),
        ("Access-Control-Max-Age", "86400"),
      ], body: Data())
      return
    }

    if config.verbose { log("\u{2192} \(req.method) \(req.path)") }

    // Get best auth token
    guard let (auth, profile) = getAuth() else {
      let msg = Data(#"{"error":{"message":"No available Codex account. Run the GUI app to set up profiles.","type":"proxy_error"}}"#.utf8)
      writeResp(fd: fd, status: 503, text: "Service Unavailable",
                headers: [("Content-Type", "application/json")], body: msg)
      return
    }

    // Forward
    let result = await forward(req, auth: auth, accountID: profile.accountID)

    switch result {
    case .ok(let code, let headers, let body):
      if code == 429 && config.autoRelay {
        if let (nextAuth, nextProfile) = getAuth(excluding: profile.id) {
          lock.withLock { failoverCount += 1 }
          log("\u{26A1} 429 failover \u{2192} \(nextProfile.displayName)")
          let retry = await forward(req, auth: nextAuth, accountID: nextProfile.accountID)
          if case .ok(let s, let h, let b) = retry {
            writeResp(fd: fd, status: s, text: statusText(s), headers: h, body: b)
            return
          }
        }
      }
      writeResp(fd: fd, status: code, text: statusText(code), headers: headers, body: body)

    case .fail(let msg):
      lock.withLock { errorCount += 1 }
      let body = Data(#"{"error":{"message":"\#(msg)","type":"proxy_error"}}"#.utf8)
      writeResp(fd: fd, status: 502, text: "Bad Gateway",
                headers: [("Content-Type", "application/json")], body: body)
    }
  }

  // MARK: - Auth

  private func getAuth(excluding: UUID? = nil) -> (AuthSnapshot, AuthProfileRecord)? {
    if let result = ProfileLoader.bestProfile(excluding: excluding) {
      return result
    }
    if excluding == nil, let (auth, profile) = ProfileLoader.activeAuth() {
      let record = profile ?? AuthProfileRecord(
        id: UUID(), fingerprint: "", snapshotFileName: "",
        authMode: auth.authMode, accountID: auth.accountID,
        email: auth.email, createdAt: .now, lastSeenAt: .now
      )
      return (auth, record)
    }
    return nil
  }

  // MARK: - Forward

  private enum FwdResult: Sendable {
    case ok(Int, [(String, String)], Data)
    case fail(String)
  }

  private func forward(_ req: HTTPReq, auth: AuthSnapshot, accountID: String?) async -> FwdResult {
    guard var comps = URLComponents(url: upstreamURL, resolvingAgainstBaseURL: false) else {
      return .fail("Invalid upstream URL")
    }

    if let qi = req.path.firstIndex(of: "?") {
      comps.path = String(req.path[req.path.startIndex..<qi])
      comps.query = String(req.path[req.path.index(after: qi)...])
    } else {
      comps.path = req.path
    }

    guard let url = comps.url else {
      return .fail("Cannot build URL for \(req.path)")
    }

    var ur = URLRequest(url: url)
    ur.httpMethod = req.method
    if !req.body.isEmpty { ur.httpBody = req.body }

    for (name, value) in req.headers {
      let low = name.lowercased()
      if low == "authorization" || low == "host" || low == "content-length" || low == "accept-encoding" { continue }
      ur.setValue(value, forHTTPHeaderField: name)
    }
    ur.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
    ur.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    if let accountID, !accountID.isEmpty {
      ur.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
    }

    do {
      let (data, resp) = try await session.data(for: ur)
      guard let http = resp as? HTTPURLResponse else { return .fail("Non-HTTP response") }

      var headers: [(String, String)] = []
      for (k, v) in http.allHeaderFields {
        let key = "\(k)"
        let low = key.lowercased()
        if low == "transfer-encoding" || low == "connection" || low == "content-length" { continue }
        headers.append((key, "\(v)"))
      }
      headers.append(("Content-Length", "\(data.count)"))
      headers.append(("Access-Control-Allow-Origin", "*"))

      if config.verbose { log("\u{2190} \(http.statusCode) \(data.count)B") }
      return .ok(http.statusCode, headers, data)
    } catch {
      return .fail(error.localizedDescription)
    }
  }

  // MARK: - HTTP I/O

  private func readHTTP(fd: Int32) -> HTTPReq? {
    var raw = Data()
    var buf = [UInt8](repeating: 0, count: 8192)
    let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])

    while raw.range(of: sep) == nil {
      let n = Darwin.read(fd, &buf, buf.count)
      if n <= 0 { return nil }
      raw.append(contentsOf: buf[0..<n])
      if raw.count > 1_048_576 { return nil }
    }

    guard let sepRange = raw.range(of: sep) else { return nil }
    let headerData = raw[raw.startIndex..<sepRange.lowerBound]
    guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }

    let lines = headerStr.components(separatedBy: "\r\n")
    guard let first = lines.first else { return nil }
    let parts = first.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2 else { return nil }

    let method = String(parts[0])
    let path = String(parts[1])

    var headers: [(String, String)] = []
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
      let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
      headers.append((name, value))
    }

    let contentLength = headers.first { $0.0.lowercased() == "content-length" }
      .flatMap { Int($0.1) } ?? 0

    let bodyStart = sepRange.upperBound
    var body = Data(raw[bodyStart...])

    while body.count < contentLength {
      let need = min(contentLength - body.count, buf.count)
      let n = Darwin.read(fd, &buf, need)
      if n <= 0 { break }
      body.append(contentsOf: buf[0..<n])
    }

    return HTTPReq(method: method, path: path, headers: headers, body: body)
  }

  private func writeResp(fd: Int32, status: Int, text: String, headers: [(String, String)], body: Data) {
    var out = "HTTP/1.1 \(status) \(text)\r\n"
    for (k, v) in headers { out += "\(k): \(v)\r\n" }
    if !headers.contains(where: { $0.0.lowercased() == "content-length" }) {
      out += "Content-Length: \(body.count)\r\n"
    }
    out += "Connection: close\r\n\r\n"

    var data = Data(out.utf8)
    data.append(body)

    data.withUnsafeBytes { ptr in
      guard let base = ptr.baseAddress else { return }
      var written = 0
      while written < data.count {
        let n = Darwin.write(fd, base + written, data.count - written)
        if n <= 0 { break }
        written += n
      }
    }
  }

  // MARK: - Helpers

  private func log(_ msg: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    print("[\(f.string(from: Date()))] \(msg)")
  }

  private func printBanner() {
    let profiles = ProfileLoader.loadProfiles().filter { $0.validationError == nil }
    let portStr = "\(config.port)"
    print("""

    \u{1F680} codex-rate proxy v\(AppVersion.current)
    \u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}
    Listen:      http://127.0.0.1:\(portStr)
    Upstream:    \(config.upstream)
    Profiles:    \(profiles.count) account(s)
    Auto-relay:  \(config.autoRelay ? "on" : "off")
    \u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}
    Usage:
      export OPENAI_API_BASE=http://127.0.0.1:\(portStr)
    Health:
      curl http://127.0.0.1:\(portStr)/health
    \u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}
    """)
    for p in profiles {
      let rem = p.latestUsage?.effectiveRemainingPercent ?? 0
      let icon = rem > 50 ? "\u{1F7E2}" : rem > 15 ? "\u{1F7E1}" : "\u{1F534}"
      print("    \(icon) \(p.displayName)  \(Int(rem))% remaining")
    }
    if profiles.isEmpty {
      print("    \u{26A0}\u{FE0F}  No profiles found. Run the GUI app to set up accounts.")
      print("       Falling back to ~/.codex/auth.json")
    }
    print()
  }

  /// Quick health probe — returns true if proxy responds on the given port.
  public static func healthCheck(port: UInt16 = 19876) async -> Bool {
    guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
    var req = URLRequest(url: url)
    req.timeoutInterval = 1.5
    req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    do {
      let (_, resp) = try await RateWatcherURLSessionFactory.shared.data(for: req)
      return (resp as? HTTPURLResponse)?.statusCode == 200
    } catch {
      return false
    }
  }

  private func statusText(_ code: Int) -> String {
    switch code {
    case 200: return "OK"
    case 201: return "Created"
    case 204: return "No Content"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 403: return "Forbidden"
    case 404: return "Not Found"
    case 429: return "Too Many Requests"
    case 500: return "Internal Server Error"
    case 502: return "Bad Gateway"
    case 503: return "Service Unavailable"
    default: return "Status \(code)"
    }
  }
}
