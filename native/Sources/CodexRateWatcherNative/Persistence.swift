import Foundation

enum AppPaths {
  static let rootDirectory: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appending(path: "CodexRateWatcherNative")
  }()

  static let samplesFile = rootDirectory.appending(path: "samples.json")
  static let profilesDirectory = rootDirectory.appending(path: "auth-profiles")
  static let profileIndexFile = rootDirectory.appending(path: "profiles.json")
  static let backupsDirectory = rootDirectory.appending(path: "auth-backups")
}

struct UsageSample: Codable {
  let capturedAt: Date
  let primaryUsedPercent: Double
  let primaryResetAt: TimeInterval
  let secondaryUsedPercent: Double?
  let secondaryResetAt: TimeInterval?
  let reviewUsedPercent: Double
  let reviewResetAt: TimeInterval
}

actor SampleStore {
  private let fileManager = FileManager.default
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init() {
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func load() async -> [UsageSample] {
    do {
      let data = try Data(contentsOf: AppPaths.samplesFile)
      return try decoder.decode([UsageSample].self, from: data)
    } catch {
      return []
    }
  }

  func append(snapshot: UsageSnapshot, capturedAt: Date) async -> [UsageSample] {
    var samples = await load()
    samples.append(
      UsageSample(
        capturedAt: capturedAt,
        primaryUsedPercent: snapshot.rateLimit.primaryWindow.usedPercent,
        primaryResetAt: snapshot.rateLimit.primaryWindow.resetAt,
        secondaryUsedPercent: snapshot.rateLimit.secondaryWindow?.usedPercent,
        secondaryResetAt: snapshot.rateLimit.secondaryWindow?.resetAt,
        reviewUsedPercent: snapshot.codeReviewRateLimit.primaryWindow.usedPercent,
        reviewResetAt: snapshot.codeReviewRateLimit.primaryWindow.resetAt
      )
    )
    samples = prune(samples)
    await save(samples)
    return samples
  }

  private func prune(_ samples: [UsageSample]) -> [UsageSample] {
    let cutoff = Date().addingTimeInterval(-10 * 24 * 60 * 60)
    return samples.filter { $0.capturedAt >= cutoff }
  }

  private func save(_ samples: [UsageSample]) async {
    let directory = AppPaths.samplesFile.deletingLastPathComponent()
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    do {
      let data = try encoder.encode(samples)
      try data.write(to: AppPaths.samplesFile, options: .atomic)
    } catch {
      return
    }
  }
}

enum AuthProfileStoreError: LocalizedError {
  case profileNotFound

  var errorDescription: String? {
    switch self {
    case .profileNotFound:
      return "The selected auth profile could not be found."
    }
  }
}

actor AuthProfileStore {
  private let fileManager = FileManager.default
  private let authStore: AuthStore
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(authStore: AuthStore = AuthStore()) {
    self.authStore = authStore
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func loadProfiles() async -> [AuthProfileRecord] {
    sortProfiles((try? readProfiles()) ?? [])
  }

  func currentProfileID() async -> UUID? {
    guard let envelope = try? authStore.loadEnvelope() else {
      return nil
    }

    let profiles = await loadProfiles()
    return profiles.first(where: { $0.fingerprint == envelope.fingerprint })?.id
  }

  func captureCurrentAuthIfNeeded() async throws -> [AuthProfileRecord] {
    let envelope = try authStore.loadEnvelope()
    return try storeEnvelopeIfNeeded(envelope)
  }

  func updateCurrentProfileValidation(snapshot: UsageSnapshot) async -> [AuthProfileRecord] {
    guard let envelope = try? authStore.loadEnvelope() else {
      return await loadProfiles()
    }

    var profiles = (try? readProfiles()) ?? []
    if let index = profiles.firstIndex(where: { $0.fingerprint == envelope.fingerprint }) {
      profiles[index].lastSeenAt = Date()
      profiles[index].lastValidatedAt = Date()
      profiles[index].latestUsage = AuthProfileUsageSummary(snapshot: snapshot)
      profiles[index].validationError = nil
      profiles[index].authMode = envelope.snapshot.authMode
      if profiles[index].accountID == nil {
        profiles[index].accountID = envelope.snapshot.accountID
      }
      try? writeProfiles(profiles)
    }

    return sortProfiles(profiles)
  }

  func validateProfiles(using apiClient: UsageAPIClient) async -> [AuthProfileRecord] {
    var profiles = (try? readProfiles()) ?? []
    let now = Date()

    for index in profiles.indices {
      let snapshotURL = AppPaths.profilesDirectory.appending(path: profiles[index].snapshotFileName)
      do {
        let data = try Data(contentsOf: snapshotURL)
        let envelope = try authStore.envelope(from: data)
        let usage = try await apiClient.fetchUsage(auth: envelope.snapshot)

        profiles[index].lastValidatedAt = now
        profiles[index].latestUsage = AuthProfileUsageSummary(snapshot: usage)
        profiles[index].validationError = nil
        profiles[index].authMode = envelope.snapshot.authMode
        if profiles[index].accountID == nil {
          profiles[index].accountID = envelope.snapshot.accountID
        }
      } catch {
        profiles[index].lastValidatedAt = now
        profiles[index].validationError = error.localizedDescription
      }
    }

    try? writeProfiles(profiles)
    return sortProfiles(profiles)
  }

  func switchToProfile(id: UUID) async throws {
    var profiles = try readProfiles()
    guard let index = profiles.firstIndex(where: { $0.id == id }) else {
      throw AuthProfileStoreError.profileNotFound
    }

    try createDirectoriesIfNeeded()

    if let currentData = try? authStore.loadRawData() {
      let backupURL = AppPaths.backupsDirectory.appending(path: "auth-\(Self.backupFormatter.string(from: Date())).json")
      try currentData.write(to: backupURL, options: .atomic)
    }

    let snapshotURL = AppPaths.profilesDirectory.appending(path: profiles[index].snapshotFileName)
    let data = try Data(contentsOf: snapshotURL)
    try authStore.writeRawData(data)
    profiles[index].lastSeenAt = Date()
    try writeProfiles(profiles)
  }

  private func storeEnvelopeIfNeeded(_ envelope: AuthEnvelope) throws -> [AuthProfileRecord] {
    try createDirectoriesIfNeeded()
    var profiles = try readProfiles()
    let now = Date()

    if let index = profiles.firstIndex(where: { $0.fingerprint == envelope.fingerprint }) {
      profiles[index].lastSeenAt = now
      profiles[index].authMode = envelope.snapshot.authMode
      if profiles[index].accountID == nil {
        profiles[index].accountID = envelope.snapshot.accountID
      }
      try writeProfiles(profiles)
      return sortProfiles(profiles)
    }

    let profileID = UUID()
    let fileName = "\(profileID.uuidString).json"
    let snapshotURL = AppPaths.profilesDirectory.appending(path: fileName)
    try envelope.rawData.write(to: snapshotURL, options: .atomic)

    profiles.append(
      AuthProfileRecord(
        id: profileID,
        fingerprint: envelope.fingerprint,
        snapshotFileName: fileName,
        authMode: envelope.snapshot.authMode,
        accountID: envelope.snapshot.accountID,
        createdAt: now,
        lastSeenAt: now,
        lastValidatedAt: nil,
        latestUsage: nil,
        validationError: nil
      )
    )

    try writeProfiles(profiles)
    return sortProfiles(profiles)
  }

  private func readProfiles() throws -> [AuthProfileRecord] {
    do {
      let data = try Data(contentsOf: AppPaths.profileIndexFile)
      return try decoder.decode([AuthProfileRecord].self, from: data)
    } catch CocoaError.fileReadNoSuchFile {
      return []
    } catch {
      throw error
    }
  }

  private func writeProfiles(_ profiles: [AuthProfileRecord]) throws {
    let sorted = sortProfiles(profiles)
    let data = try encoder.encode(sorted)
    try data.write(to: AppPaths.profileIndexFile, options: .atomic)
  }

  private func createDirectoriesIfNeeded() throws {
    try fileManager.createDirectory(at: AppPaths.rootDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: AppPaths.profilesDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: AppPaths.backupsDirectory, withIntermediateDirectories: true)
  }

  private func sortProfiles(_ profiles: [AuthProfileRecord]) -> [AuthProfileRecord] {
    profiles.sorted { lhs, rhs in
      if lhs.lastSeenAt != rhs.lastSeenAt {
        return lhs.lastSeenAt > rhs.lastSeenAt
      }
      return lhs.createdAt > rhs.createdAt
    }
  }

  private static let backupFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter
  }()
}
