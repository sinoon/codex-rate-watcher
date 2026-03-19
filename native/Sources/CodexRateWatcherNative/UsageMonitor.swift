import Foundation

@MainActor
final class UsageMonitor {
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

    var lastUpdatedLabel: String {
      guard let lastUpdatedAt else {
        return "Waiting for the first successful sync"
      }
      return "Updated \(RelativeDateTimeFormatter().localizedString(for: lastUpdatedAt, relativeTo: .now))"
    }

    var footerMessage: String? {
      guard let snapshot else { return nil }

      if let weeklyWindow = snapshot.rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "Weekly limit is exhausted for the active account. Access stays blocked until \(resetLabel(for: weeklyWindow))."
      }

      if snapshot.rateLimit.primaryWindow.remainingPercent <= 0 {
        return "The 5h window is exhausted. Access resumes at \(resetLabel(for: snapshot.rateLimit.primaryWindow))."
      }

      if !snapshot.rateLimit.allowed || snapshot.rateLimit.limitReached {
        return "This account is currently blocked by its rate limit state."
      }

      if snapshot.credits.hasCredits {
        return "Credits are available as a fallback if your primary window is exhausted."
      }

      return "Polling every minute from ~/.codex/auth.json using the same usage endpoint Codex reads."
    }

    func availabilityLabel(for rateLimit: UsageLimit) -> String {
      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "Blocked"
      }

      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "Blocked"
      }

      if !rateLimit.allowed || rateLimit.limitReached {
        return "Blocked"
      }

      return "Available"
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
        return "Weekly left \(weeklyLeft). 5h still has \(primaryLeft), but access is blocked until \(resetLabel(for: weeklyWindow))."
      }

      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "5h left 0% and weekly left \(weeklyLeft). Access resumes at \(resetLabel(for: rateLimit.primaryWindow))."
      }

      if !rateLimit.allowed || rateLimit.limitReached {
        return "This account is blocked even though some quota remains. Check the next reset window before switching back."
      }

      if let weeklyWindow = rateLimit.secondaryWindow {
        return "5h left \(primaryLeft) · Weekly left \(weeklyWindow.remainingPercentLabel)"
      }

      return "5h left \(primaryLeft)"
    }

    func statusLine(for window: LimitWindow) -> String {
      if window.remainingPercent <= 0 {
        return "Exhausted"
      }

      return "Available"
    }

    func remainingLabel(for window: LimitWindow) -> String {
      window.remainingPercentLabel
    }

    func resetLine(for window: LimitWindow) -> String {
      let countdown = Date(timeIntervalSince1970: window.resetAt).timeIntervalSinceNow
      if countdown <= 0 {
        return "Resetting now"
      }

      return "Resets in \(countdown.condensedDuration) · \(resetLabel(for: window))"
    }

    func primaryBurnLabel(for rateLimit: UsageLimit) -> String {
      if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
        return "Weekly blocked. 5h window itself still has \(rateLimit.primaryWindow.remainingPercentLabel)."
      }

      if rateLimit.primaryWindow.remainingPercent <= 0 {
        return "No 5h quota left until \(resetLabel(for: rateLimit.primaryWindow))."
      }

      return burnLabel(from: primaryEstimate)
    }

    func weeklyBurnLabel(for rateLimit: UsageLimit) -> String {
      guard let weeklyWindow = rateLimit.secondaryWindow else {
        return secondaryEstimate.statusText
      }

      if weeklyWindow.remainingPercent <= 0 {
        return "No weekly quota left until \(resetLabel(for: weeklyWindow))."
      }

      return burnLabel(from: secondaryEstimate)
    }

    func resetLabel(for window: LimitWindow) -> String {
      let date = Date(timeIntervalSince1970: window.resetAt)
      let formatter = DateFormatter()
      formatter.locale = Locale.autoupdatingCurrent
      formatter.dateFormat = Calendar.current.isDate(date, equalTo: .now, toGranularity: .day) ? "HH:mm" : "d MMM"
      return formatter.string(from: date)
    }

    func burnLabel(from estimate: BurnEstimate) -> String {
      if let timeUntilExhausted = estimate.timeUntilExhausted {
        return "At this pace, fully drains in \(timeUntilExhausted.condensedDuration)."
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
  private var primaryEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "Collecting a few more minutes of data before estimating.")
  private var secondaryEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "Collecting a few more samples for the weekly trend.")
  private var reviewEstimate = BurnEstimate(timeUntilExhausted: nil, percentPerHour: nil, statusText: "Collecting a few more samples for code review usage.")
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
        return "\(days)d \(hours)h"
      }
      return "\(days)d"
    }

    if hours > 0 {
      if minutes > 0 {
        return "\(hours)h \(minutes)m"
      }
      return "\(hours)h"
    }

    return "\(max(1, minutes))m"
  }
}
