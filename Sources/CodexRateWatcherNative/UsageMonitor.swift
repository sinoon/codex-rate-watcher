import Foundation
import CodexRateKit

@MainActor
final class UsageMonitor {
  struct SwitchRecommendation {
    enum Kind {
      case syncing
      case stay
      case switchNow
      case noAvailable
    }

    let kind: Kind
    let headline: String
    let detail: String
    let recommendedProfileID: UUID?
  }

  struct State {
    let snapshot: UsageSnapshot?
    let profiles: [AuthProfileRecord]
    let activeProfileID: UUID?
    let errorMessage: String?
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let isAddingAccount: Bool
    let tokenCostSnapshot: TokenCostSnapshot?
    let primaryEstimate: BurnEstimate
    let secondaryEstimate: BurnEstimate
    let reviewEstimate: BurnEstimate

    var switchRecommendation: SwitchRecommendation {
      buildSwitchRecommendation()
    }

    var relayPlan: RelayPlan {
      let inputs = RelayPlanner.inputs(from: profiles, activeProfileID: activeProfileID)
      return RelayPlanner.plan(
        profiles: inputs,
        currentBurnRate: primaryEstimate.percentPerHour,
        strategy: .resetAware
      )
    }

    var relaySummary: String {
      let plan = relayPlan
      guard !plan.legs.isEmpty else { return Copy.relayNoAccounts }
      let coverage = Copy.relayCoverage(duration: plan.coverageSummary, legCount: plan.legCount)
      if plan.canSurviveUntilReset {
        let resetLabel = plan.earliestPrimaryReset.map { Copy.resetDate($0.timeIntervalSince1970) } ?? "--"
        return "\(coverage) · \(Copy.relaySurvive(resetTime: resetLabel))"
      }
      return coverage
    }

    var lastUpdatedLabel: String {
      guard let lastUpdatedAt else {
        return "等待首次同步"  // Keep — only shown once
      }
      return "更新于 \(RelativeDateTimeFormatter().localizedString(for: lastUpdatedAt, relativeTo: .now))"
    }

    var footerMessage: String? {
      if isAddingAccount {
        return Copy.addAccountInProgress
      }
      guard let snapshot else { return nil }

      if let weeklyWindow = snapshot.rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return Copy.footerExhausted(label: "周额度", resetAt: weeklyWindow.resetAt)
      }

      if snapshot.rateLimit.primaryWindow.remainingPercent <= 0 {
        return Copy.footerExhausted(label: "5h额度", resetAt: snapshot.rateLimit.primaryWindow.resetAt)
      }

      if !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached {
        return Copy.footerThrottled
      }

      if snapshot.credits.hasCredits {
        return Copy.footerHasCredits
      }

      return Copy.footerAutoRefresh
    }

    func availabilityLabel(for rateLimit: UsageLimit) -> String {
      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "不可用"
      }
      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "不可用"
      }
      if !rateLimit.allowed || rateLimit.limitReached {
        return "不可用"
      }
      if rateLimit.primaryWindow.remainingPercent <= 15 {
        return "即将耗尽"
      }
      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 15 {
        return "即将耗尽"
      }
      return "可用"
    }

    func availabilityDetail(for rateLimit: UsageLimit) -> String {
      let primaryLeft = rateLimit.primaryWindow.remainingPercentLabel
      _ = rateLimit.secondaryWindow?.remainingPercentLabel

      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "周额度耗尽 · \(Copy.resetDate(weeklyWindow.resetAt)) 重置"
      }
      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "已耗尽 · \(Copy.resetDate(rateLimit.primaryWindow.resetAt)) 重置"
      }
      if !rateLimit.allowed || rateLimit.limitReached {
        return Copy.footerThrottled
      }
      if let weeklyWindow = rateLimit.secondaryWindow {
        return "5h 剩 \(primaryLeft) · 周 剩 \(weeklyWindow.remainingPercentLabel)"
      }
      return "5h 剩 \(primaryLeft)"
    }

    func statusLine(for window: LimitWindow) -> String {
      if window.remainingPercent <= 0 { return Copy.exhausted }
      if window.remainingPercent <= 15 { return Copy.runningLow }
      return Copy.available
    }

    func remainingLabel(for window: LimitWindow) -> String {
      window.remainingPercentLabel
    }

    func resetLine(for window: LimitWindow) -> String {
      let countdown = Date(timeIntervalSince1970: window.resetAt).timeIntervalSinceNow
      if countdown <= 0 { return Copy.resetting }
      return "\(Copy.duration(countdown)) 后重置 · \(resetLabel(for: window))"
    }

    func primaryBurnLabel(for rateLimit: UsageLimit) -> String {
      let reset = resetLabel(for: rateLimit.primaryWindow)
      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return Copy.footerExhausted(label: "周额度", resetAt: weeklyWindow.resetAt)
      }
      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "\(reset) 重置"
      }
      if let t = primaryEstimate.timeUntilExhausted {
        return "预计 \(t.condensedDuration) 后耗尽，\(reset) 重置"
      }
      return "\(reset) 重置 · \(primaryEstimate.statusText)"
    }

    func weeklyBurnLabel(for rateLimit: UsageLimit) -> String {
      guard let weeklyWindow = rateLimit.secondaryWindow else {
        return secondaryEstimate.statusText
      }
      if weeklyWindow.remainingPercent <= 0 {
        return Copy.heroExhausted(resetAt: weeklyWindow.resetAt)
      }
      return Copy.quotaBurn(timeLeft: secondaryEstimate.timeUntilExhausted, resetAt: weeklyWindow.resetAt)
    }

    func resetLabel(for window: LimitWindow) -> String {
      Copy.resetDate(window.resetAt)
    }

    func burnLabel(from estimate: BurnEstimate) -> String {
      if let t = estimate.timeUntilExhausted {
        return Copy.reviewBurn(timeLeft: t)
      }
      return estimate.statusText
    }

    var validProfileCount: Int {
      profiles.filter(\.isValid).count
    }

    var availableProfileCount: Int {
      profiles.filter { profile in
        profile.validationError == nil && (profile.latestUsage?.isBlocked == false)
      }.count
    }

    private func buildSwitchRecommendation() -> SwitchRecommendation {
      let currentProfile = profiles.first(where: { $0.id == activeProfileID })
      let rankedProfiles = rankedReadyProfiles()
      let waitingProfiles = rankedWaitingProfiles(excluding: activeProfileID)

      guard snapshot != nil else {
        return SwitchRecommendation(
          kind: .syncing,
          headline: Copy.recComputing,
          detail: Copy.recComputingDetail,
          recommendedProfileID: nil
        )
      }

      guard let bestProfile = rankedProfiles.first else {
        let fallbackDetail: String
        if let waitingProfile = waitingProfiles.first,
           let waitingUsage = waitingProfile.latestUsage {
          fallbackDetail = "暂无可立即切换账号 · 最近恢复 \(waitingProfile.displayName) (\(waitingUsage.switchSummaryText))"
        } else if let currentProfile, let currentUsage = currentProfile.latestUsage {
          fallbackDetail = "\(currentProfile.displayName) \(Copy.unavailable) (\(currentUsage.switchSummaryText))"
        } else {
          fallbackDetail = "无可切账号，等重置"
        }

        return SwitchRecommendation(
          kind: .noAvailable,
          headline: Copy.recNoAvailable,
          detail: fallbackDetail,
          recommendedProfileID: nil
        )
      }

      let backupProfile = rankedProfiles.dropFirst().first ?? waitingProfiles.first
      let currentScore = currentProfile.flatMap { score(for: $0, isCurrent: true) }
      let bestScore = score(for: bestProfile, isCurrent: bestProfile.id == activeProfileID) ?? 0

      if let currentProfile,
         currentProfile.id == bestProfile.id,
         let currentUsage = currentProfile.latestUsage,
         !currentUsage.isBlocked {
        return SwitchRecommendation(
          kind: .stay,
          headline: currentUsage.isRunningLow ? Copy.recStayLow : Copy.recStay,
          detail: stayDetail(for: currentProfile, backupProfile: backupProfile),
          recommendedProfileID: nil
        )
      }

      if let currentProfile,
         let currentUsage = currentProfile.latestUsage,
         !currentUsage.isBlocked,
         let currentScore,
         currentProfile.id != bestProfile.id,
         bestScore - currentScore < 12,
         !currentUsage.isRunningLow {
        return SwitchRecommendation(
          kind: .stay,
          headline: Copy.recNoSwitch,
          detail: stayDetail(for: currentProfile, backupProfile: bestProfile),
          recommendedProfileID: nil
        )
      }

      return SwitchRecommendation(
        kind: .switchNow,
        headline: Copy.recSwitch(to: bestProfile.displayName),
        detail: switchDetail(recommendedProfile: bestProfile, currentProfile: currentProfile, backupProfile: backupProfile),
        recommendedProfileID: bestProfile.id
      )
    }

    private func rankedReadyProfiles() -> [AuthProfileRecord] {
      profiles
        .compactMap { profile -> (AuthProfileRecord, Double)? in
          guard let score = score(for: profile, isCurrent: profile.id == activeProfileID) else {
            return nil
          }
          return (profile, score)
        }
        .sorted { lhs, rhs in
          if lhs.1 == rhs.1 {
            return (lhs.0.lastValidatedAt ?? .distantPast) > (rhs.0.lastValidatedAt ?? .distantPast)
          }
          return lhs.1 > rhs.1
        }
        .map(\.0)
    }

    private func rankedWaitingProfiles(excluding excludedID: UUID?) -> [AuthProfileRecord] {
      profiles
        .filter { profile in
          profile.id != excludedID && profile.isWaitingForReset
        }
        .sorted { lhs, rhs in
          let lhsReset = lhs.latestUsage?.nextBlockingResetAt ?? .greatestFiniteMagnitude
          let rhsReset = rhs.latestUsage?.nextBlockingResetAt ?? .greatestFiniteMagnitude
          if lhsReset == rhsReset {
            return (lhs.lastValidatedAt ?? .distantPast) > (rhs.lastValidatedAt ?? .distantPast)
          }
          return lhsReset < rhsReset
        }
    }

    func score(for profile: AuthProfileRecord, isCurrent: Bool) -> Double? {
      guard profile.isReadyForImmediateSwitch, let usage = profile.latestUsage else {
        return nil
      }

      let primary = usage.primaryRemainingPercent
      let weekly = usage.secondaryRemainingPercent ?? 100
      let balanced = min(primary, weekly)
      let reviewRemaining = max(0, 100 - usage.reviewUsedPercent)

      var score = balanced * 3.2
      score += primary * 1.1
      score += weekly * 0.45
      score += reviewRemaining * 0.08

      if usage.isRunningLow {
        score -= 28
      }

      if isCurrent {
        score += 4
      }

      return score
    }

    private func stayDetail(for currentProfile: AuthProfileRecord, backupProfile: AuthProfileRecord?) -> String {
      guard let currentUsage = currentProfile.latestUsage else {
        return Copy.syncing
      }
      let backup: (name: String, summary: String)? = backupProfile.flatMap { bp in
        bp.latestUsage.map { (bp.displayName, $0.switchSummaryText) }
      }
      return Copy.stayDetail(
        current: currentUsage.switchSummaryText,
        backup: backup,
        isLow: currentUsage.isRunningLow
      )
    }

    private func switchDetail(
      recommendedProfile: AuthProfileRecord,
      currentProfile: AuthProfileRecord?,
      backupProfile: AuthProfileRecord?
    ) -> String {
      let recSummary = recommendedProfile.latestUsage?.switchSummaryText ?? Copy.syncing
      let current: (String, String)?
      if let cp = currentProfile, let cu = cp.latestUsage {
        current = (cp.displayName, cu.switchSummaryText)
      } else {
        current = nil
      }
      let backup: (name: String, summary: String)?
      if let bp = backupProfile, bp.id != recommendedProfile.id, let bu = bp.latestUsage {
        backup = (bp.displayName, bu.switchSummaryText)
      } else {
        backup = nil
      }
      return Copy.switchDetail(
        recommended: recommendedProfile.displayName, recommendedSummary: recSummary,
        current: current?.0, currentSummary: current?.1,
        backup: backup
      )
    }
  }

  private let authStore: AuthStore
  private let apiClient: UsageAPIClient
  private let tokenRefresher = TokenRefresher()
  private let tokenCostLoader: TokenCostSnapshotLoading
  private let larkSignatureAutoSync: LarkSignatureAutoSyncing
  private let sampleStore: SampleStore
  private let profileStore: AuthProfileStore
  private let managedAccountService: ManagedCodexAccountService
  private var timer: Timer?
  private var authWatcher: AuthFileWatcher?
  private var authChangeTask: Task<Void, Never>?
  private var snapshot: UsageSnapshot?
  private var profiles: [AuthProfileRecord] = []
  private var activeProfileID: UUID?
  private var errorMessage: String?
  private var lastUpdatedAt: Date?
  private var lastProfilesValidationAt: Date?
  private var isRefreshing = false
  private var isAddingAccount = false
  private var tokenCostSnapshot: TokenCostSnapshot?
  private var samples: [UsageSample] = []
  private var primaryEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: Copy.sampling)
  private var secondaryEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: Copy.sampling)
  private var reviewEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: Copy.sampling)
  // MARK: - Auto-Switch

  struct AutoSwitchConfig: Equatable {
    var enabled: Bool = false

    static let disabled = AutoSwitchConfig()
  }

  private let clearPersistedAutoSwitchConfig: () -> Void
  private(set) var autoSwitchConfig: AutoSwitchConfig

  private var observers: [UUID: (State) -> Void] = [:]

  init(
    authStore: AuthStore = AuthStore(),
    apiClient: UsageAPIClient = UsageAPIClient(),
    tokenCostLoader: TokenCostSnapshotLoading = LiveTokenCostSnapshotLoader(),
    larkSignatureAutoSync: LarkSignatureAutoSyncing = LarkSignatureAutoSyncService(),
    sampleStore: SampleStore = SampleStore(),
    profileStore: AuthProfileStore? = nil,
    managedAccountService: ManagedCodexAccountService = ManagedCodexAccountService(),
    clearPersistedAutoSwitchConfig: @escaping () -> Void = UsageMonitor.clearPersistedAutoSwitchConfig
  ) {
    self.authStore = authStore
    self.apiClient = apiClient
    self.tokenCostLoader = tokenCostLoader
    self.larkSignatureAutoSync = larkSignatureAutoSync
    self.sampleStore = sampleStore
    self.profileStore = profileStore ?? AuthProfileStore(authStore: authStore)
    self.managedAccountService = managedAccountService
    self.clearPersistedAutoSwitchConfig = clearPersistedAutoSwitchConfig
    self.autoSwitchConfig = .disabled
    self.clearPersistedAutoSwitchConfig()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    authWatcher?.stop()
    authWatcher = nil
    authChangeTask?.cancel()
    authChangeTask = nil
  }
  // MARK: - Auto-Switch Control

  func setAutoSwitch(enabled: Bool) {
    autoSwitchConfig = .disabled
    clearPersistedAutoSwitchConfig()
    if enabled {
      NSLog("[UsageMonitor] Auto-switch is disabled and cannot be enabled")
    } else {
      NSLog("[UsageMonitor] Auto-switch disabled")
    }
  }

  nonisolated private static func clearPersistedAutoSwitchConfig() {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("CodexRateWatcherNative", isDirectory: true)
    let url = dir.appendingPathComponent("auto-switch-config.json")
    try? FileManager.default.removeItem(at: url)
  }



  func addObserver(_ handler: @escaping (State) -> Void) -> UUID {
    let id = UUID()
    observers[id] = handler
    handler(makeState())
    return id
  }

  func removeObserver(_ id: UUID) {
    observers.removeValue(forKey: id)
  }

  func start() {
    guard timer == nil else { return }
    setupAuthWatcher()

    Task {
      self.samples = await sampleStore.load()
      do {
        self.profiles = try await profileStore.captureCurrentAuthIfNeeded()
      } catch {
        self.errorMessage = error.localizedDescription
      }
      self.activeProfileID = await profileStore.currentProfileID()
      emitState()
      await refresh(manual: false, refreshProfiles: true)

      timer?.invalidate()
      timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        Task { await self?.tick() }
      }
    }
  }

  func refresh(manual: Bool, refreshProfiles: Bool = false) async {
    guard !isRefreshing else { return }
    await performRefresh(manual: manual, refreshProfiles: refreshProfiles, manageLoadingState: true)
  }

  func addManagedAccount(timeout: TimeInterval = 300) async throws -> ManagedCodexAccount {
    guard !isAddingAccount else {
      throw NSError(domain: "CodexRateWatcherNative", code: 1, userInfo: [
        NSLocalizedDescriptionKey: Copy.addAccountAlreadyRunning
      ])
    }

    isAddingAccount = true
    emitState()
    defer {
      isAddingAccount = false
      emitState()
    }

    let account = try await managedAccountService.authenticateManagedAccount(timeout: timeout)
    profiles = try await profileStore.syncManagedAccount(account)
    activeProfileID = await profileStore.currentProfileID()
    errorMessage = nil
    await performRefresh(manual: true, refreshProfiles: true, manageLoadingState: false)
    return account
  }

  func switchToProfile(id: UUID) async {
    guard !isRefreshing else { return }
    isRefreshing = true
    emitState()

    do {
      try await profileStore.switchToProfile(id: id)
      do {
        profiles = try await profileStore.captureCurrentAuthIfNeeded()
      } catch {
        profiles = await profileStore.loadProfiles()
      }
      activeProfileID = await profileStore.currentProfileID()
      errorMessage = nil
      await performRefresh(manual: true, refreshProfiles: true, manageLoadingState: false)
    } catch {
      errorMessage = error.localizedDescription
    }

    isRefreshing = false
    emitState()
  }

  private func tick() async {
    let shouldValidateProfiles: Bool
    if let lastProfilesValidationAt {
      shouldValidateProfiles = Date().timeIntervalSince(lastProfilesValidationAt) > 5 * 60
    } else {
      shouldValidateProfiles = true
    }

    await refresh(manual: false, refreshProfiles: shouldValidateProfiles)
  }

  private func performRefresh(manual: Bool, refreshProfiles: Bool, manageLoadingState: Bool) async {
    if manageLoadingState {
      isRefreshing = true
      emitState()
    }

    defer {
      if manageLoadingState {
        isRefreshing = false
        emitState()
      }
    }

    do {
      profiles = (try? await profileStore.captureCurrentAuthIfNeeded()) ?? profiles
      let auth = try authStore.load()
      let freshSnapshot: UsageSnapshot
      do {
        freshSnapshot = try await apiClient.fetchUsage(auth: auth)
      } catch let apiError as UsageAPIError {
        // On 401, attempt automatic token refresh before giving up.
        if case .httpError(statusCode: 401, _) = apiError {
          freshSnapshot = try await refreshTokenAndRetry()
        } else {
          throw apiError
        }
      }
      let now = Date()

      snapshot = freshSnapshot
      errorMessage = nil
      lastUpdatedAt = now
      samples = await sampleStore.append(snapshot: freshSnapshot, capturedAt: now)
      rebuildEstimates()
      tokenCostSnapshot = await tokenCostLoader.loadSnapshot(now: now)
      if let tokenCostSnapshot {
        await larkSignatureAutoSync.syncIfNeeded(snapshot: tokenCostSnapshot, now: now)
      }

      profiles = (try? await profileStore.captureCurrentAuthIfNeeded()) ?? profiles
      profiles = await profileStore.updateCurrentProfileValidation(snapshot: freshSnapshot)
      activeProfileID = await profileStore.currentProfileID()

      if refreshProfiles {
        profiles = await profileStore.validateProfiles(using: apiClient)
        activeProfileID = await profileStore.currentProfileID()
        lastProfilesValidationAt = Date()
      }
    } catch {
      errorMessage = error.localizedDescription
      let fallbackNow = Date()
      tokenCostSnapshot = await tokenCostLoader.loadSnapshot(now: fallbackNow)
      if let tokenCostSnapshot {
        await larkSignatureAutoSync.syncIfNeeded(snapshot: tokenCostSnapshot, now: fallbackNow)
      }
      if manual {
        lastUpdatedAt = fallbackNow
      }

      if refreshProfiles {
        profiles = await profileStore.validateProfiles(using: apiClient)
        activeProfileID = await profileStore.currentProfileID()
        lastProfilesValidationAt = Date()
      } else {
        profiles = await profileStore.loadProfiles()
        activeProfileID = await profileStore.currentProfileID()
      }
    }
  }

  /// Use the refresh_token to obtain a fresh access_token, persist it, then
  /// retry the usage API call once.
  private func refreshTokenAndRetry() async throws -> UsageSnapshot {
    NSLog("[UsageMonitor] Access token expired (401). Attempting token refresh…")

    let rawData = try authStore.loadRawData()
    let updatedData = try await tokenRefresher.refresh(currentAuthData: rawData)
    try authStore.writeRawData(updatedData)

    NSLog("[UsageMonitor] Token refresh succeeded, retrying usage fetch")

    // Re-read the freshly persisted auth and retry.
    let freshAuth = try authStore.load()
    return try await apiClient.fetchUsage(auth: freshAuth)
  }

  private func rebuildEstimates() {
    guard let snapshot else { return }
    primaryEstimate = UsageEstimator.estimatePrimary(from: samples, window: snapshot.rateLimit.primaryWindow)
    if let weeklyWindow = snapshot.rateLimit.secondaryWindow {
      secondaryEstimate = UsageEstimator.estimateSecondary(from: samples, window: weeklyWindow)
    }
    reviewEstimate = UsageEstimator.estimateReview(from: samples, window: snapshot.codeReviewRateLimit.primaryWindow)
  }

  private func emitState() {
    let state = makeState()
    for handler in observers.values {
      handler(state)
    }
  }

  private func makeState() -> State {
    State(
      snapshot: snapshot,
      profiles: profiles,
      activeProfileID: activeProfileID,
      errorMessage: errorMessage,
      lastUpdatedAt: lastUpdatedAt,
      isRefreshing: isRefreshing,
      isAddingAccount: isAddingAccount,
      tokenCostSnapshot: tokenCostSnapshot,
      primaryEstimate: primaryEstimate,
      secondaryEstimate: secondaryEstimate,
      reviewEstimate: reviewEstimate
    )
  }

  private func setupAuthWatcher() {
    guard authWatcher == nil else { return }

    let watcher = AuthFileWatcher(directoryURL: authStore.watchedDirectoryURL)
    watcher.onChange = { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        self.scheduleWatchedAuthSync()
      }
    }
    watcher.start()
    authWatcher = watcher
  }

  private func scheduleWatchedAuthSync() {
    authChangeTask?.cancel()
    authChangeTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      await self?.handleObservedAuthChange()
    }
  }

  private func handleObservedAuthChange() async {
    do {
      profiles = try await profileStore.captureCurrentAuthIfNeeded()
      activeProfileID = await profileStore.currentProfileID()
      emitState()
      await refresh(manual: false, refreshProfiles: true)
    } catch {
      errorMessage = error.localizedDescription
      emitState()
    }
  }
}

extension TimeInterval {
  var condensedDuration: String {
    Copy.duration(self)
  }
}
