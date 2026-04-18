import Foundation
import CodexRateKit

actor SampleStore {
  private let fileManager = FileManager.default
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let fileURL: URL

  init(fileURL: URL = AppPaths.samplesFile) {
    self.fileURL = fileURL
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func load() async -> [UsageSample] {
    do {
      let data = try Data(contentsOf: fileURL)
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
    let directory = fileURL.deletingLastPathComponent()
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    do {
      let data = try encoder.encode(samples)
      try data.write(to: fileURL, options: .atomic)
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

struct AuthProfileStorePaths {
  let rootDirectory: URL
  let profilesDirectory: URL
  let profileIndexFile: URL
  let backupsDirectory: URL

  static let live = AuthProfileStorePaths(
    rootDirectory: AppPaths.rootDirectory,
    profilesDirectory: AppPaths.profilesDirectory,
    profileIndexFile: AppPaths.profileIndexFile,
    backupsDirectory: AppPaths.backupsDirectory
  )
}

actor AuthProfileStore {
  private let fileManager = FileManager.default
  private let authStore: AuthStore
  private let managedAccountStore: ManagedCodexAccountStoring
  private let paths: AuthProfileStorePaths
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var hasReconciled = false

  init(
    authStore: AuthStore = AuthStore(),
    managedAccountStore: ManagedCodexAccountStoring = FileManagedCodexAccountStore(),
    paths: AuthProfileStorePaths = .live
  ) {
    self.authStore = authStore
    self.managedAccountStore = managedAccountStore
    self.paths = paths
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func loadProfiles() async -> [AuthProfileRecord] {
    normalizeProfilesFromSnapshots()
  }

  func currentProfileID() async -> UUID? {
    guard let envelope = try? authStore.loadEnvelope() else {
      return nil
    }

    let profiles = await loadProfiles()
    // Match by fingerprint first, then fall back to accountID
    if let match = profiles.first(where: { $0.fingerprint == envelope.fingerprint }) {
      return match.id
    }
    if let accountID = envelope.snapshot.accountID {
      return profiles.first(where: { $0.accountID == accountID })?.id
    }
    return nil
  }

  func captureCurrentAuthIfNeeded() async throws -> [AuthProfileRecord] {
    // Reconcile and deduplicate on first call
    if !hasReconciled {
      reconcileOrphanedSnapshots()
      _ = normalizeProfilesFromSnapshots()
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
    // Match by fingerprint first, then fall back to accountID
    let index = profiles.firstIndex(where: { $0.fingerprint == envelope.fingerprint })
      ?? (envelope.snapshot.accountID.flatMap { acctID in profiles.firstIndex(where: { $0.accountID == acctID }) })
    if let index {
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

  func syncManagedAccount(_ account: ManagedCodexAccount) async throws -> [AuthProfileRecord] {
    let managedAuthStore = AuthStore(fileURL: managedAuthURL(for: account))
    let envelope = try managedAuthStore.loadEnvelope()
    return try storeEnvelopeIfNeeded(envelope)
  }

  func validateProfiles(using apiClient: UsageAPIClient) async -> [AuthProfileRecord] {
    var profiles = normalizeProfilesFromSnapshots()
    let now = Date()
    syncManagedSnapshotsIfNeeded(for: profiles)

    for index in profiles.indices {
      let snapshotURL = paths.profilesDirectory.appending(path: profiles[index].snapshotFileName)
      do {
        let data = try Data(contentsOf: snapshotURL)
        let envelope = try authStore.envelope(from: data)
        let usage = try await apiClient.fetchUsage(auth: envelope.snapshot)

        profiles[index].lastValidatedAt = now
        profiles[index].latestUsage = AuthProfileUsageSummary(snapshot: usage)
        profiles[index].validationError = nil
        profiles[index].fingerprint = envelope.fingerprint
        profiles[index].authMode = envelope.snapshot.authMode
        profiles[index].accountID = envelope.snapshot.accountID
        profiles[index].email = envelope.snapshot.email
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
      let backupURL = paths.backupsDirectory.appending(path: "auth-\(Self.backupFormatter.string(from: Date())).json")
      try currentData.write(to: backupURL, options: .atomic)
    }

    let data = try loadPreferredAuthData(for: profiles[index])
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
      at: paths.profilesDirectory,
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

      // Skip if same accountID already tracked (token refreshed → different fingerprint)
      if let accountID = envelope.snapshot.accountID,
         profiles.contains(where: { $0.accountID == accountID }) {
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
    syncManagedHomeIfNeeded(for: envelope)
    var profiles = try readProfiles()
    let now = Date()

    // Match by fingerprint (exact same auth data)
    if let index = profiles.firstIndex(where: { $0.fingerprint == envelope.fingerprint }) {
      profiles[index].lastSeenAt = now
      profiles[index].fingerprint = envelope.fingerprint
      profiles[index].authMode = envelope.snapshot.authMode
      profiles[index].accountID = envelope.snapshot.accountID
      profiles[index].email = envelope.snapshot.email
      try writeProfiles(profiles)
      return sortProfiles(profiles)
    }

    // Match by accountID (same account, token refreshed → different fingerprint)
    if let accountID = envelope.snapshot.accountID,
       let index = profiles.firstIndex(where: { $0.accountID == accountID }) {
      // Update existing profile with new snapshot
      let snapshotURL = paths.profilesDirectory.appending(path: profiles[index].snapshotFileName)
      try envelope.rawData.write(to: snapshotURL, options: .atomic)
      profiles[index].fingerprint = envelope.fingerprint
      profiles[index].lastSeenAt = now
      profiles[index].authMode = envelope.snapshot.authMode
      profiles[index].accountID = envelope.snapshot.accountID
      profiles[index].email = envelope.snapshot.email
      try writeProfiles(profiles)
      return sortProfiles(profiles)
    }

    let profileID = UUID()
    let fileName = "\(profileID.uuidString).json"
    let snapshotURL = paths.profilesDirectory.appending(path: fileName)
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

  private func syncManagedHomeIfNeeded(for envelope: AuthEnvelope) {
    guard let accountID = normalizeAccountID(envelope.snapshot.accountID),
          let managedAccounts = try? managedAccountStore.loadAccounts(),
          let account = managedAccounts.accounts.first(where: {
            normalizeAccountID($0.accountID) == accountID
          }) else {
      return
    }

    let managedURL = managedAuthURL(for: account)
    let existingData = try? Data(contentsOf: managedURL)
    guard existingData != envelope.rawData else {
      return
    }

    try? fileManager.createDirectory(
      at: managedURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try? envelope.rawData.write(to: managedURL, options: .atomic)
  }

  private func readProfiles() throws -> [AuthProfileRecord] {
    do {
      let data = try Data(contentsOf: paths.profileIndexFile)
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
    try data.write(to: paths.profileIndexFile, options: .atomic)
  }

  private func createDirectoriesIfNeeded() throws {
    try fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: paths.profilesDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: paths.backupsDirectory, withIntermediateDirectories: true)
  }

  private func normalizeProfilesFromSnapshots() -> [AuthProfileRecord] {
    let profiles = (try? readProfiles()) ?? []
    guard !profiles.isEmpty else { return [] }

    let synced = synchronizeStoredMetadataWithSnapshots(profiles)
    let deduplicated = deduplicateProfiles(synced.profiles)

    if synced.changed || !deduplicated.removed.isEmpty {
      for removedProfile in deduplicated.removed {
        let url = paths.profilesDirectory.appending(path: removedProfile.snapshotFileName)
        try? fileManager.removeItem(at: url)
      }
      try? writeProfiles(deduplicated.profiles)
    }

    return sortProfiles(deduplicated.profiles)
  }

  private func synchronizeStoredMetadataWithSnapshots(
    _ profiles: [AuthProfileRecord]
  ) -> (profiles: [AuthProfileRecord], changed: Bool) {
    var synced = profiles
    var changed = false

    for index in synced.indices {
      let snapshotURL = paths.profilesDirectory.appending(path: synced[index].snapshotFileName)
      guard let data = try? Data(contentsOf: snapshotURL),
            let envelope = try? authStore.envelope(from: data) else {
        continue
      }

      let normalizedEmail = normalizeEmail(envelope.snapshot.email)
      if synced[index].fingerprint != envelope.fingerprint {
        synced[index].fingerprint = envelope.fingerprint
        changed = true
      }
      if synced[index].authMode != envelope.snapshot.authMode {
        synced[index].authMode = envelope.snapshot.authMode
        changed = true
      }
      if synced[index].accountID != envelope.snapshot.accountID {
        synced[index].accountID = envelope.snapshot.accountID
        changed = true
      }
      if normalizeEmail(synced[index].email) != normalizedEmail {
        synced[index].email = normalizedEmail
        changed = true
      }
    }

    return (synced, changed)
  }

  private func deduplicateProfiles(
    _ profiles: [AuthProfileRecord]
  ) -> (profiles: [AuthProfileRecord], removed: [AuthProfileRecord]) {
    guard profiles.count > 1 else {
      return (profiles, [])
    }

    var seen: [String: Int] = [:]
    var toRemove: Set<Int> = []

    for (index, profile) in profiles.enumerated() {
      guard let key = deduplicationKey(for: profile) else { continue }

      if let existingIndex = seen[key] {
        let existing = profiles[existingIndex]
        if shouldPrefer(profile, over: existing) {
          toRemove.insert(existingIndex)
          seen[key] = index
        } else {
          toRemove.insert(index)
        }
      } else {
        seen[key] = index
      }
    }

    guard !toRemove.isEmpty else {
      return (profiles, [])
    }

    let removed = profiles.enumerated().compactMap { toRemove.contains($0.offset) ? $0.element : nil }
    let cleaned = profiles.enumerated().compactMap { toRemove.contains($0.offset) ? nil : $0.element }
    return (cleaned, removed)
  }

  private func syncManagedSnapshotsIfNeeded(for profiles: [AuthProfileRecord]) {
    guard let managedAccounts = try? managedAccountStore.loadAccounts() else {
      return
    }

    for profile in profiles {
      guard let account = matchingManagedAccount(for: profile, accounts: managedAccounts.accounts) else {
        continue
      }
      guard let data = try? Data(contentsOf: managedAuthURL(for: account)) else {
        continue
      }
      let snapshotURL = paths.profilesDirectory.appending(path: profile.snapshotFileName)
      try? data.write(to: snapshotURL, options: .atomic)
    }
  }

  private func loadPreferredAuthData(for profile: AuthProfileRecord) throws -> Data {
    if let managedAccounts = try? managedAccountStore.loadAccounts(),
       let account = matchingManagedAccount(for: profile, accounts: managedAccounts.accounts) {
      let managedURL = managedAuthURL(for: account)
      if fileManager.fileExists(atPath: managedURL.path) {
        let data = try Data(contentsOf: managedURL)
        let snapshotURL = paths.profilesDirectory.appending(path: profile.snapshotFileName)
        try? data.write(to: snapshotURL, options: .atomic)
        return data
      }
    }

    let snapshotURL = paths.profilesDirectory.appending(path: profile.snapshotFileName)
    return try Data(contentsOf: snapshotURL)
  }

  private func matchingManagedAccount(
    for profile: AuthProfileRecord,
    accounts: [ManagedCodexAccount]
  ) -> ManagedCodexAccount? {
    if let accountID = normalizeAccountID(profile.accountID),
       let match = accounts.first(where: { normalizeAccountID($0.accountID) == accountID }) {
      return match
    }
    return nil
  }

  private func managedAuthURL(for account: ManagedCodexAccount) -> URL {
    URL(fileURLWithPath: account.managedHomePath, isDirectory: true).appending(path: "auth.json")
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

  private func deduplicationKey(for profile: AuthProfileRecord) -> String? {
    if let accountID = normalizeAccountID(profile.accountID) {
      return "account:\(accountID)"
    }
    if !profile.fingerprint.isEmpty {
      return "fingerprint:\(profile.fingerprint)"
    }
    return nil
  }

  private func shouldPrefer(_ candidate: AuthProfileRecord, over existing: AuthProfileRecord) -> Bool {
    if candidate.lastSeenAt != existing.lastSeenAt {
      return candidate.lastSeenAt > existing.lastSeenAt
    }
    if candidate.lastValidatedAt != existing.lastValidatedAt {
      return (candidate.lastValidatedAt ?? .distantPast) > (existing.lastValidatedAt ?? .distantPast)
    }
    return candidate.createdAt > existing.createdAt
  }

  private func normalizeAccountID(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }

  private func normalizeEmail(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }

  private static let backupFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter
  }()
}
