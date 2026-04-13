import Foundation

struct TokenCostDeviceStore: @unchecked Sendable {
  private let fileURL: URL
  private let fileManager: FileManager
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    fileURL: URL = AppPaths.tokenCostDeviceFile,
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func loadOrCreateDevice(now: Date = Date()) throws -> TokenCostSyncDevice {
    if let data = try? Data(contentsOf: fileURL),
       let device = try? decoder.decode(TokenCostSyncDevice.self, from: data) {
      return device
    }

    let device = TokenCostSyncDevice(
      deviceID: UUID().uuidString.lowercased(),
      deviceName: Host.current().localizedName ?? "Mac",
      createdAt: now
    )
    try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try encoder.encode(device)
    try data.write(to: fileURL, options: .atomic)
    return device
  }
}
