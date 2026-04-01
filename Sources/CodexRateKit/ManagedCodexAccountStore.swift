import Foundation

public protocol ManagedCodexAccountStoring: Sendable {
  func loadAccounts() throws -> ManagedCodexAccountSet
  func storeAccounts(_ accounts: ManagedCodexAccountSet) throws
}

public struct FileManagedCodexAccountStore: @unchecked Sendable, ManagedCodexAccountStoring {
  public static let currentVersion = 1

  private let fileURL: URL
  private let fileManager: FileManager
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(
    fileURL: URL = AppPaths.managedCodexAccountsFile,
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  public func loadAccounts() throws -> ManagedCodexAccountSet {
    do {
      let data = try Data(contentsOf: fileURL)
      return try decoder.decode(ManagedCodexAccountSet.self, from: data)
    } catch CocoaError.fileReadNoSuchFile {
      return ManagedCodexAccountSet(version: Self.currentVersion, accounts: [])
    }
  }

  public func storeAccounts(_ accounts: ManagedCodexAccountSet) throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let payload = ManagedCodexAccountSet(version: Self.currentVersion, accounts: accounts.accounts)
    let data = try encoder.encode(payload)
    try data.write(to: fileURL, options: .atomic)
  }
}
