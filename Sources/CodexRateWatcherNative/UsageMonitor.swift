import Foundation

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
    let primaryEstimate: BurnEstimate
    let secondaryEstimate: BurnEstimate
    let reviewEstimate: BurnEstimate

    var switchRecommendation: SwitchRecommendation {
      buildSwitchRecommendation()
    }

    var lastUpdatedLabel: String {
      guard let lastUpdatedAt else {
        return "正在等第一次同步"
      }
      return "上次更新：\(RelativeDateTimeFormatter().localizedString(for: lastUpdatedAt, relativeTo: .now))"
    }

    var footerMessage: String? {
      guard let snapshot else { return nil }

      if let weeklyWindow = snapshot.rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "这个账号的本周主额度已经用完了，要等到 \(resetLabel(for: weeklyWindow)) 才会恢复。"
      }

      if snapshot.rateLimit.primaryWindow.remainingPercent <= 0 {
        return "这个账号近 5 小时主额度已经用完了，要等到 \(resetLabel(for: snapshot.rateLimit.primaryWindow)) 才会恢复。"
      }

      if !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached {
        return "这个账号现在被限流状态拦住了，建议先切到别的账号。"
      }

      if snapshot.credits.hasCredits {
        return "这个账号还有 credits，可以在主额度之外作为兜底。"
      }

      return "我会每分钟自动刷新一次，也会在你切换登录账号后自动识别。"
    }

    func availabilityLabel(for rateLimit: UsageLimit) -> String {
      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "现在不可用"
      }

      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "现在不可用"
      }

      if !rateLimit.allowed || rateLimit.limitReached {
        return "现在不可用"
      }

      if rateLimit.primaryWindow.remainingPercent <= 15 {
        return "快见底了"
      }

      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 15 {
        return "快见底了"
      }

      return "现在可用"
    }

    func availabilityDetail(for rateLimit: UsageLimit) -> String {
      let primaryLeft = rateLimit.primaryWindow.remainingPercentLabel
      let weeklyLeft: String
      if let weeklyWindow = rateLimit.secondaryWindow {
        weeklyLeft = weeklyWindow.remainingPercentLabel
      } else {
        weeklyLeft = "--"
      }

      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "本周主额度已经用完。虽然近 5 小时还剩 \(primaryLeft)，但现在也不能继续用了，要等到 \(resetLabel(for: weeklyWindow)) 恢复。"
      }

      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "近 5 小时主额度已经用完，本周主额度还剩 \(weeklyLeft)。要等到 \(resetLabel(for: rateLimit.primaryWindow)) 恢复。"
      }

      if !rateLimit.allowed || rateLimit.limitReached {
        return "这个账号虽然看起来还有剩余，但当前还是不可用，建议先切到别的账号。"
      }

      if let weeklyWindow = rateLimit.secondaryWindow {
        return "近 5 小时主额度还剩 \(primaryLeft)，本周主额度还剩 \(weeklyWindow.remainingPercentLabel)。"
      }

      return "近 5 小时主额度还剩 \(primaryLeft)。"
    }

    func statusLine(for window: LimitWindow) -> String {
      if window.remainingPercent <= 0 {
        return "已用完"
      }

      if window.remainingPercent <= 15 {
        return "快见底了"
      }

      return "还有剩余"
    }

    func remainingLabel(for window: LimitWindow) -> String {
      window.remainingPercentLabel
    }

    func resetLine(for window: LimitWindow) -> String {
      let countdown = Date(timeIntervalSince1970: window.resetAt).timeIntervalSinceNow
      if countdown <= 0 {
        return "正在重置"
      }

      return "大约 \(countdown.condensedDuration) 后重置 · \(resetLabel(for: window))"
    }

    func primaryBurnLabel(for rateLimit: UsageLimit) -> String {
      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "虽然近 5 小时这桶还剩 \(rateLimit.primaryWindow.remainingPercentLabel)，但因为本周主额度已经用完，现在也不能继续用了。"
      }

      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "近 5 小时主额度已经见底了，等到 \(resetLabel(for: rateLimit.primaryWindow)) 会恢复。"
      }

      return burnLabel(from: primaryEstimate)
    }

    func weeklyBurnLabel(for rateLimit: UsageLimit) -> String {
      guard let weeklyWindow = rateLimit.secondaryWindow else {
        return secondaryEstimate.statusText
      }

      if weeklyWindow.remainingPercent <= 0 {
        return "本周主额度已经见底了，等到 \(resetLabel(for: weeklyWindow)) 会恢复。"
      }

      return burnLabel(from: secondaryEstimate)
    }

    func resetLabel(for window: LimitWindow) -> String {
      let date = Date(timeIntervalSince1970: window.resetAt)
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "zh_Hans_CN")
      formatter.dateFormat = Calendar.current.isDate(date, equalTo: .now, toGranularity: .day) ? "HH:mm" : "M月d日"
      return formatter.string(from: date)
    }

    func burnLabel(from estimate: BurnEstimate) -> String {
      if let timeUntilExhausted = estimate.timeUntilExhausted {
        return "按现在这个速度，大约 \(timeUntilExhausted.condensedDuration) 后会用完。"
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

      guard snapshot != nil else {
        return SwitchRecommendation(
          kind: .syncing,
          headline: "还在计算推荐",
          detail: "等第一轮额度和账号池校验完成后，我会告诉你先用哪个、下一个该切谁。",
          recommendedProfileID: nil
        )
      }

      guard let bestProfile = rankedProfiles.first else {
        let fallbackDetail: String
        if let currentProfile, let currentUsage = currentProfile.latestUsage {
          fallbackDetail = "\(currentProfile.displayName) 现在也不可用，最近一轮是 \(currentUsage.switchSummaryText)。先等额度重置后再看。"
        } else {
          fallbackDetail = "账号池里暂时没有可立即切过去的账号，先等下一轮刷新或额度重置。"
        }

        return SwitchRecommendation(
          kind: .noAvailable,
          headline: "现在没有更优的可用账号",
          detail: fallbackDetail,
          recommendedProfileID: nil
        )
      }

      let backupProfile = rankedProfiles.dropFirst().first
      let currentScore = currentProfile.flatMap { score(for: $0, isCurrent: true) }
      let bestScore = score(for: bestProfile, isCurrent: bestProfile.id == activeProfileID) ?? 0

      if let currentProfile,
         currentProfile.id == bestProfile.id,
         let currentUsage = currentProfile.latestUsage,
         !currentUsage.isBlocked {
        return SwitchRecommendation(
          kind: .stay,
          headline: currentUsage.isRunningLow ? "先继续用当前账号，准备下一跳" : "先继续用 \(currentProfile.displayName)",
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
          headline: "当前账号先不用急着切",
          detail: stayDetail(for: currentProfile, backupProfile: bestProfile),
          recommendedProfileID: nil
        )
      }

      return SwitchRecommendation(
        kind: .switchNow,
        headline: "建议切到 \(bestProfile.displayName)",
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

    private func score(for profile: AuthProfileRecord, isCurrent: Bool) -> Double? {
      guard profile.validationError == nil, let usage = profile.latestUsage, !usage.isBlocked else {
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
        return "当前账号还在同步校验，先保持现状。"
      }

      if currentUsage.isRunningLow, let backupProfile, let backupUsage = backupProfile.latestUsage {
        return "\(currentProfile.displayName) 虽然已经快见底了，但它仍然比其他账号更能撑。你可以先把这一轮用完，再切到 \(backupProfile.displayName)；后者目前是 \(backupUsage.switchSummaryText)。"
      }

      if let backupProfile, let backupUsage = backupProfile.latestUsage {
        return "\(currentProfile.displayName) 现在的综合余量仍然最划算，先继续用它。等它接近见底时，再切到 \(backupProfile.displayName)；后者目前是 \(backupUsage.switchSummaryText)。"
      }

      return "\(currentProfile.displayName) 现在最稳，当前剩余是 \(currentUsage.switchSummaryText)。先继续用它就好。"
    }

    private func switchDetail(
      recommendedProfile: AuthProfileRecord,
      currentProfile: AuthProfileRecord?,
      backupProfile: AuthProfileRecord?
    ) -> String {
      let recommendedUsageText = recommendedProfile.latestUsage?.switchSummaryText ?? "剩余信息还在同步"
      let currentText: String

      if let currentProfile, let currentUsage = currentProfile.latestUsage {
        currentText = "当前账号 \(currentProfile.displayName) 只有 \(currentUsage.switchSummaryText)。"
      } else {
        currentText = "当前账号信息还不完整，所以先按已校验账号来推荐。"
      }

      let backupText: String
      if let backupProfile, backupProfile.id != recommendedProfile.id, let backupUsage = backupProfile.latestUsage {
        backupText = "如果后面还要继续跑，下一顺位是 \(backupProfile.displayName)（\(backupUsage.switchSummaryText)）。"
      } else {
        backupText = "目前没有第二个更好的候补账号。"
      }

      return "\(recommendedProfile.displayName) 现在最能撑，\(recommendedUsageText)。\(currentText)\(backupText)"
    }
  }

  private let authStore: AuthStore
  private let apiClient: UsageAPIClient
  private let sampleStore: SampleStore
  private let profileStore: AuthProfileStore
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
  private var samples: [UsageSample] = []
  private var primaryEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "还在收集样本，过几分钟后我再估算多久会用完。")
  private var secondaryEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "还在收集样本，过几分钟后我再估算本周额度的消耗速度。")
  private var reviewEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "还在收集样本，过几分钟后我再估算代码审查额度的消耗速度。")
  private var observers: [UUID: (State) -> Void] = [:]

  init(
    authStore: AuthStore = AuthStore(),
    apiClient: UsageAPIClient = UsageAPIClient(),
    sampleStore: SampleStore = SampleStore(),
    profileStore: AuthProfileStore? = nil
  ) {
    self.authStore = authStore
    self.apiClient = apiClient
    self.sampleStore = sampleStore
    self.profileStore = profileStore ?? AuthProfileStore(authStore: authStore)
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    authWatcher?.stop()
    authWatcher = nil
    authChangeTask?.cancel()
    authChangeTask = nil
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
      let freshSnapshot = try await apiClient.fetchUsage(auth: auth)
      let now = Date()

      snapshot = freshSnapshot
      errorMessage = nil
      lastUpdatedAt = now
      samples = await sampleStore.append(snapshot: freshSnapshot, capturedAt: now)
      rebuildEstimates()
      profiles = await profileStore.updateCurrentProfileValidation(snapshot: freshSnapshot)
      activeProfileID = await profileStore.currentProfileID()

      if refreshProfiles {
        profiles = await profileStore.validateProfiles(using: apiClient)
        activeProfileID = await profileStore.currentProfileID()
        lastProfilesValidationAt = Date()
      }
    } catch {
      errorMessage = error.localizedDescription
      if manual {
        lastUpdatedAt = Date()
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

private extension TimeInterval {
  var condensedDuration: String {
    let totalMinutes = max(0, Int(self / 60))
    let days = totalMinutes / (60 * 24)
    let hours = (totalMinutes % (60 * 24)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
      if hours > 0 {
        return "\(days)天\(hours)小时"
      }
      return "\(days)天"
    }

    if hours > 0 {
      if minutes > 0 {
        return "\(hours)小时\(minutes)分钟"
      }
      return "\(hours)小时"
    }

    return "\(max(1, minutes))分钟"
  }
}
