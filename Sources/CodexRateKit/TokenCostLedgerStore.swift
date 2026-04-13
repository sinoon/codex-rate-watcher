import Foundation

struct TokenCostLedgerStore: @unchecked Sendable {
  private let localLedgerFileURL: URL
  private let iCloudLedgerDirectoryURL: URL
  private let fileManager: FileManager
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    localLedgerFileURL: URL = AppPaths.tokenCostLocalLedgerFile,
    iCloudLedgerDirectoryURL: URL = AppPaths.iCloudLedgerDirectory,
    fileManager: FileManager = .default
  ) {
    self.localLedgerFileURL = localLedgerFileURL
    self.iCloudLedgerDirectoryURL = iCloudLedgerDirectoryURL
    self.fileManager = fileManager
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func saveLocalLedger(_ ledger: TokenCostSyncLedger) throws {
    try save(ledger, to: localLedgerFileURL)
  }

  func loadLocalLedger() -> TokenCostSyncLedger? {
    loadLedger(from: localLedgerFileURL)
  }

  func saveLedgerToICloud(_ ledger: TokenCostSyncLedger) throws {
    let fileURL = iCloudLedgerDirectoryURL.appending(path: "\(ledger.device.deviceID).json")
    try save(ledger, to: fileURL)
  }

  func loadICloudLedgers() -> [TokenCostSyncLedger] {
    guard let contents = try? fileManager.contentsOfDirectory(
      at: iCloudLedgerDirectoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    return contents
      .filter { $0.pathExtension == "json" }
      .compactMap(loadLedger(from:))
      .sorted { lhs, rhs in
        if lhs.updatedAt != rhs.updatedAt {
          return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.device.deviceID < rhs.device.deviceID
      }
  }

  private func save(_ ledger: TokenCostSyncLedger, to fileURL: URL) throws {
    try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try encoder.encode(ledger)
    try data.write(to: fileURL, options: .atomic)
  }

  private func loadLedger(from fileURL: URL) -> TokenCostSyncLedger? {
    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }
    return try? decoder.decode(TokenCostSyncLedger.self, from: data)
  }
}
