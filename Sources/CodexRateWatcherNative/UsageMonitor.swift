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
    let primaryEstimate: BurnEstimate
    let secondaryEstimate: BurnEstimate
    let reviewEstimate: BurnEstimate

    var switchRecommendation: SwitchRecommendation {
      buildSwitchRecommendation()
    }

    var lastUpdatedLabel: String {
      guard let lastUpdatedAt else {
        return "等待首次同步"
      }
      return "更新于 \(RelativeDateTimeFormatter().localizedString(for: lastUpdatedAt, relativeTo: .now))"
    }

    var footerMessage: String? {
      guard let snapshot else { return nil }

      if let weeklyWindow = snapshot.rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "本周额度耗尽，\(resetLabel(for: weeklyWindow)) 重置"
      }

      if snapshot.rateLimit.primaryWindow.remainingPercent <= 0 {
        return "5h 额度耗尽，\(resetLabel(for: snapshot.rateLimit.primaryWindow)) 重置"
      }

      if !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached {
        return "当前账号被限流，建议切换"
      }

      if snapshot.credits.hasCredits {
        return "有 credits 兜底"
      }

      return "每分钟自动刷新"
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
        return "本周额度已耗尽，\(resetLabel(for: weeklyWindow)) 重置"
      }
      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "5h 额度已耗尽，\(resetLabel(for: rateLimit.primaryWindow)) 重置"
      }
      if !rateLimit.allowed || rateLimit.limitReached {
        return "账号被限流，建议切换其他账号"
      }
      if let weeklyWindow = rateLimit.secondaryWindow {
        return "5h 剩 \(primaryLeft) · 周 剩 \(weeklyWindow.remainingPercentLabel)"
      }
      return "5h 剩 \(primaryLeft)"
    }

    func statusLine(for window: LimitWindow) -> String {
      if window.remainingPercent <= 0 { return "已耗尽" }
      if window.remainingPercent <= 15 { return "即将耗尽" }
      return "正常"
    }

    func remainingLabel(for window: LimitWindow) -> String {
      window.remainingPercentLabel
    }

    func resetLine(for window: LimitWindow) -> String {
      let countdown = Date(timeIntervalSince1970: window.resetAt).timeIntervalSinceNow
      if countdown <= 0 { return "重置中" }
      return "\(countdown.condensedDuration) 后重置 · \(resetLabel(for: window))"
    }

    func primaryBurnLabel(for rateLimit: UsageLimit) -> String {
      let reset = resetLabel(for: rateLimit.primaryWindow)
      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "本周额度耗尽，\(resetLabel(for: weeklyWindow)) 重置"
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
      let reset = resetLabel(for: weeklyWindow)
      if weeklyWindow.remainingPercent <= 0 {
        return "\(reset) 重置"
      }
      if let t = secondaryEstimate.timeUntilExhausted {
        return "预计 \(t.condensedDuration) 后耗尽，\(reset) 重置"
      }
      return "\(reset) 重置 · \(secondaryEstimate.statusText)"
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
        return "预计 \(timeUntilExhausted.condensedDuration) 后耗尽"
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
          headline: "正在计算",
          detail: "首轮校验完成后给出建议",
          recommendedProfileID: nil
        )
      }

      guard let bestProfile = rankedProfiles.first else {
        let fallbackDetail: String
        if let currentProfile, let currentUsage = currentProfile.latestUsage {
          fallbackDetail = "\(currentProfile.displayName) 不可用（\(currentUsage.switchSummaryText)），等重置"
        } else {
          fallbackDetail = "无可切账号，等额度重置"
        }

        return SwitchRecommendation(
          kind: .noAvailable,
          headline: "无更优账号",
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
          headline: currentUsage.isRunningLow ? "当前最优，准备下一跳" : "继续用当前账号",
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
          headline: "暂不需要切换",
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
        return "当前账号同步中"
      }

      if currentUsage.isRunningLow, let backupProfile, let backupUsage = backupProfile.latestUsage {
        return "余量低但仍最优，用完后切 \(backupProfile.displayName)（\(backupUsage.switchSummaryText)）"
      }

      if let backupProfile, let backupUsage = backupProfile.latestUsage {
        return "余量最优，备选 \(backupProfile.displayName)（\(backupUsage.switchSummaryText)）"
      }

      return "余量最优，\(currentUsage.switchSummaryText)"
    }

    private func switchDetail(
      recommendedProfile: AuthProfileRecord,
      currentProfile: AuthProfileRecord?,
      backupProfile: AuthProfileRecord?
    ) -> String {
      let recommendedUsageText = recommendedProfile.latestUsage?.switchSummaryText ?? "同步中"
      let currentText: String

      if let currentProfile, let currentUsage = currentProfile.latestUsage {
        currentText = "当前 \(currentProfile.displayName) 仅 \(currentUsage.switchSummaryText)"
      } else {
        currentText = "当前账号信息不完整"
      }

      let backupText: String
      if let backupProfile, backupProfile.id != recommendedProfile.id, let backupUsage = backupProfile.latestUsage {
        backupText = " · 备选 \(backupProfile.displayName)（\(backupUsage.switchSummaryText)）"
      } else {
        backupText = ""
      }

      return "\(recommendedProfile.displayName) 余量最多（\(recommendedUsageText)）· \(currentText)\(backupText)"
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
  private var primaryEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "收集样本中")
  private var secondaryEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "收集样本中")
  private var reviewEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "收集样本中")
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

extension TimeInterval {
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
        return "\(hours)h\(minutes)min"
      }
      return "\(hours)h"
    }

    return "\(max(1, minutes))min"
  }
}
