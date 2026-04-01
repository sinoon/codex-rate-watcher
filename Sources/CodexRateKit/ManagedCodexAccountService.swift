import Foundation

public protocol ManagedCodexHomeProducing: Sendable {
  func makeHomeURL() -> URL
  func validateManagedHomeForDeletion(_ url: URL) throws
}

public protocol ManagedCodexLoginRunning: Sendable {
  func run(homePath: String, timeout: TimeInterval) async -> CodexLoginRunner.Result
}

public enum ManagedCodexAccountServiceError: LocalizedError, Equatable {
  case missingCodexCLI
  case loginTimedOut
  case loginFailed(String)
  case missingEmail
  case missingAuthFile
  case unsafeManagedHome(String)

  public var errorDescription: String? {
    switch self {
    case .missingCodexCLI:
      return "未找到 codex CLI，请先确认 `codex` 已安装并能在终端里运行。"
    case .loginTimedOut:
      return "浏览器登录超时，请重试。"
    case .loginFailed(let message):
      if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "Codex 登录失败，请重试。"
      }
      return "Codex 登录失败：\(message)"
    case .missingEmail:
      return "登录成功了，但当前账号信息里没有可识别的邮箱。"
    case .missingAuthFile:
      return "登录流程结束后，没有在托管账号目录里找到 auth.json。"
    case .unsafeManagedHome(let path):
      return "拒绝删除不安全的托管目录：\(path)"
    }
  }
}

public struct ManagedCodexHomeFactory: ManagedCodexHomeProducing {
  public let root: URL

  public init(root: URL = AppPaths.managedCodexHomesDirectory) {
    self.root = root
  }

  public func makeHomeURL() -> URL {
    root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
  }

  public func validateManagedHomeForDeletion(_ url: URL) throws {
    let standardizedRoot = root.standardizedFileURL.path
    let standardizedTarget = url.standardizedFileURL.path
    let rootPrefix = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"
    guard standardizedTarget.hasPrefix(rootPrefix), standardizedTarget != standardizedRoot else {
      throw ManagedCodexAccountServiceError.unsafeManagedHome(url.path)
    }
  }
}

public struct DefaultManagedCodexLoginRunner: ManagedCodexLoginRunning {
  public init() {}

  public func run(homePath: String, timeout: TimeInterval) async -> CodexLoginRunner.Result {
    await CodexLoginRunner().run(homePath: homePath, timeout: timeout)
  }
}

public final class ManagedCodexAccountService: @unchecked Sendable {
  private let store: ManagedCodexAccountStoring
  private let homeFactory: ManagedCodexHomeProducing
  private let loginRunner: ManagedCodexLoginRunning
  private let fileManager: FileManager

  public init(
    store: ManagedCodexAccountStoring = FileManagedCodexAccountStore(),
    homeFactory: ManagedCodexHomeProducing = ManagedCodexHomeFactory(),
    loginRunner: ManagedCodexLoginRunning = DefaultManagedCodexLoginRunner(),
    fileManager: FileManager = .default
  ) {
    self.store = store
    self.homeFactory = homeFactory
    self.loginRunner = loginRunner
    self.fileManager = fileManager
  }

  public func authenticateManagedAccount(
    existingAccountID: UUID? = nil,
    timeout: TimeInterval = 120
  ) async throws -> ManagedCodexAccount {
    let snapshot = try store.loadAccounts()
    let homeURL = homeFactory.makeHomeURL()
    try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)

    let oldHomePath: String?
    let account: ManagedCodexAccount

    do {
      let result = await loginRunner.run(homePath: homeURL.path, timeout: timeout)
      switch result.outcome {
      case .success:
        break
      case .missingBinary:
        throw ManagedCodexAccountServiceError.missingCodexCLI
      case .timedOut:
        throw ManagedCodexAccountServiceError.loginTimedOut
      case .failed(let status):
        let message = result.output.isEmpty ? "退出码 \(status)" : result.output
        throw ManagedCodexAccountServiceError.loginFailed(message)
      case .launchFailed(let message):
        throw ManagedCodexAccountServiceError.loginFailed(message)
      }

      let authURL = homeURL.appending(path: "auth.json")
      guard fileManager.fileExists(atPath: authURL.path) else {
        throw ManagedCodexAccountServiceError.missingAuthFile
      }

      let auth = try AuthStore(fileURL: authURL).load()
      guard let email = auth.email?.trimmingCharacters(in: .whitespacesAndNewlines),
            !email.isEmpty else {
        throw ManagedCodexAccountServiceError.missingEmail
      }

      let normalizedEmail = Self.normalizeEmail(email)
      let normalizedAccountID = Self.normalizeAccountID(auth.accountID)
      let now = Date()
      let existing = existingAccountID.flatMap { snapshot.account(id: $0) }
        ?? normalizedAccountID.flatMap { accountID in
          snapshot.accounts.first { Self.normalizeAccountID($0.accountID) == accountID }
        }
      oldHomePath = existing?.managedHomePath

      account = ManagedCodexAccount(
        id: existing?.id ?? UUID(),
        email: normalizedEmail,
        managedHomePath: homeURL.path,
        accountID: auth.accountID,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        lastAuthenticatedAt: now
      )

      let remaining = snapshot.accounts.filter {
        if $0.id == account.id {
          return false
        }
        if let normalizedAccountID,
           Self.normalizeAccountID($0.accountID) == normalizedAccountID {
          return false
        }
        return true
      }
      try store.storeAccounts(
        ManagedCodexAccountSet(version: snapshot.version, accounts: remaining + [account])
      )
    } catch {
      try? removeManagedHomeIfSafe(atPath: homeURL.path)
      throw error
    }

    if let oldHomePath, oldHomePath != homeURL.path {
      try? removeManagedHomeIfSafe(atPath: oldHomePath)
    }

    return account
  }

  public func removeManagedAccount(id: UUID) throws {
    let snapshot = try store.loadAccounts()
    guard let account = snapshot.account(id: id) else { return }
    try removeManagedHomeIfSafe(atPath: account.managedHomePath)
    let remaining = snapshot.accounts.filter { $0.id != id }
    try store.storeAccounts(
      ManagedCodexAccountSet(version: snapshot.version, accounts: remaining)
    )
  }

  private func removeManagedHomeIfSafe(atPath path: String) throws {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try homeFactory.validateManagedHomeForDeletion(url)
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  private static func normalizeEmail(_ email: String) -> String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func normalizeAccountID(_ accountID: String?) -> String? {
    guard let trimmed = accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }
}
