import Foundation
import CodexRateKit

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
      return "没找到你刚才选中的那份账号档案。"
    }
  }
}

actor AuthProfileStore {
  private let fileManager = FileManager.default
  private let authStore: AuthStore
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var hasReconciled = false

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
    // Reconcile orphaned snapshots on first call
    if !hasReconciled {
      reconcileOrphanedSnapshots()
      hasReconciled = true
    }

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
        if profiles[index].email == nil {
          profiles[index].email = envelope.snapshot.email
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

  // MARK: - Reconcile orphaned snapshot files

  /// Scan auth-profiles/ directory for .json files not tracked in profiles.json,
  /// parse them to extract fingerprint/email/accountID, and register them into the index.
  private func reconcileOrphanedSnapshots() {
    do {
      try createDirectoriesIfNeeded()
    } catch {
      return
    }

    var profiles = (try? readProfiles()) ?? []
    let trackedFileNames = Set(profiles.map(\.snapshotFileName))
    let now = Date()
    var didChange = false

    guard let files = try? fileManager.contentsOfDirectory(
      at: AppPaths.profilesDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return
    }

    for fileURL in files {
      guard fileURL.pathExtension == "json" else { continue }
      let fileName = fileURL.lastPathComponent

      // Skip files already tracked
      if trackedFileNames.contains(fileName) { continue }

      // Try to parse the snapshot file
      guard let data = try? Data(contentsOf: fileURL),
            let envelope = try? authStore.envelope(from: data) else {
        continue
      }

      // Skip if same fingerprint already tracked (different filename, same content)
      if profiles.contains(where: { $0.fingerprint == envelope.fingerprint }) {
        continue
      }

      // Derive UUID from the filename if it's a valid UUID, otherwise generate new
      let stem = fileURL.deletingPathExtension().lastPathComponent
      let profileID = UUID(uuidString: stem) ?? UUID()

      profiles.append(
        AuthProfileRecord(
          id: profileID,
          fingerprint: envelope.fingerprint,
          snapshotFileName: fileName,
          authMode: envelope.snapshot.authMode,
          accountID: envelope.snapshot.accountID,
          email: envelope.snapshot.email,
          createdAt: now,
          lastSeenAt: now,
          lastValidatedAt: nil,
          latestUsage: nil,
          validationError: nil
        )
      )
      didChange = true
    }

    if didChange {
      try? writeProfiles(profiles)
    }
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
        email: envelope.snapshot.email,
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

  /// Sort profiles by availability: usable first (by remaining% desc), then
  /// running-low, then blocked/errored, then unvalidated.
  /// Within the same tier, sort by effective remaining percent descending,
  /// then by lastSeenAt descending as tiebreaker.
  private func sortProfiles(_ profiles: [AuthProfileRecord]) -> [AuthProfileRecord] {
    profiles.sorted { lhs, rhs in
      let lhsTier = availabilityTier(for: lhs)
      let rhsTier = availabilityTier(for: rhs)

      if lhsTier != rhsTier {
        return lhsTier < rhsTier  // lower tier number = higher priority
      }

      // Within same tier, sort by effective remaining percent descending
      let lhsPct = lhs.latestUsage?.effectiveAvailablePercent ?? -1
      let rhsPct = rhs.latestUsage?.effectiveAvailablePercent ?? -1
      if lhsPct != rhsPct {
        return lhsPct > rhsPct
      }

      // Tiebreaker: most recently seen first
      if lhs.lastSeenAt != rhs.lastSeenAt {
        return lhs.lastSeenAt > rhs.lastSeenAt
      }
      return lhs.createdAt > rhs.createdAt
    }
  }

  /// Tier 0: usable and not running low
  /// Tier 1: usable but running low
  /// Tier 2: blocked (exhausted / not allowed)
  /// Tier 3: validation error (e.g. 401, 402)
  /// Tier 4: not yet validated
  private func availabilityTier(for profile: AuthProfileRecord) -> Int {
    if profile.validationError != nil {
      return 3
    }
    guard let usage = profile.latestUsage else {
      return 4
    }
    if usage.isBlocked {
      return 2
    }
    if usage.isRunningLow {
      return 1
    }
    return 0
  }

  private static let backupFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter
  }()
}
