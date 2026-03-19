import AppKit

final class PopoverViewController: NSViewController {
  private let monitor: UsageMonitor
  private var observerID: UUID?

  private let updatedLabel = NSTextField(labelWithString: "Waiting for the first successful sync")
  private let refreshButton = NSButton()
  private let footerLabel = NSTextField(labelWithString: "")
  private let errorLabel = NSTextField(wrappingLabelWithString: "")
  private let currentAuthCard = CurrentAuthCardView()
  private let profilesSummaryLabel = NSTextField(labelWithString: "")
  private let profilesStack = NSStackView()
  private let profilesEmptyLabel = NSTextField(labelWithString: "No saved auth profiles yet.")

  private let primaryCard = LimitCardView(title: "5h left")
  private let weeklyCard = LimitCardView(title: "Weekly left")
  private let reviewCard = LimitCardView(title: "Review left")

  init(monitor: UsageMonitor) {
    self.monitor = monitor
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 520))
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
    observerID = monitor.addObserver { [weak self] state in
      DispatchQueue.main.async {
        self?.render(state: state)
      }
    }
  }

  deinit {
    if let observerID {
      let monitor = monitor
      Task { @MainActor in
        monitor.removeObserver(observerID)
      }
    }
  }

  private func setupUI() {
    let background = NSVisualEffectView()
    background.translatesAutoresizingMaskIntoConstraints = false
    background.material = .hudWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 22
    background.layer?.masksToBounds = true
    view.addSubview(background)

    let content = NSStackView()
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 14
    content.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    background.addSubview(content)

    let header = NSStackView()
    header.orientation = .horizontal
    header.alignment = .top
    header.spacing = 12

    let iconContainer = NSView()
    iconContainer.wantsLayer = true
    iconContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    iconContainer.layer?.cornerRadius = 18
    iconContainer.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      iconContainer.widthAnchor.constraint(equalToConstant: 36),
      iconContainer.heightAnchor.constraint(equalToConstant: 36)
    ])

    let iconView = NSImageView(image: NSImage(systemSymbolName: "speedometer", accessibilityDescription: nil) ?? NSImage())
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.contentTintColor = .white
    iconContainer.addSubview(iconView)
    NSLayoutConstraint.activate([
      iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
    ])

    let titleLabel = NSTextField(labelWithString: "Rate limits remaining")
    titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
    titleLabel.textColor = .white

    updatedLabel.font = .systemFont(ofSize: 12, weight: .medium)
    updatedLabel.textColor = .white.withAlphaComponent(0.58)

    let headerText = NSStackView(views: [titleLabel, updatedLabel])
    headerText.orientation = .vertical
    headerText.spacing = 4

    refreshButton.bezelStyle = .texturedRounded
    refreshButton.isBordered = false
    refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
    refreshButton.contentTintColor = .white
    refreshButton.wantsLayer = true
    refreshButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
    refreshButton.layer?.cornerRadius = 10
    refreshButton.translatesAutoresizingMaskIntoConstraints = false
    refreshButton.target = self
    refreshButton.action = #selector(refreshTapped)
    NSLayoutConstraint.activate([
      refreshButton.widthAnchor.constraint(equalToConstant: 30),
      refreshButton.heightAnchor.constraint(equalToConstant: 30)
    ])

    let spacer = NSView()
    header.addArrangedSubview(iconContainer)
    header.addArrangedSubview(headerText)
    header.addArrangedSubview(spacer)
    header.addArrangedSubview(refreshButton)

    let cards = NSStackView(views: [primaryCard, weeklyCard, reviewCard])
    cards.orientation = .vertical
    cards.spacing = 12

    let profilesHeaderLabel = NSTextField(labelWithString: "Saved auth profiles")
    profilesHeaderLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    profilesHeaderLabel.textColor = .white

    profilesSummaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
    profilesSummaryLabel.textColor = .white.withAlphaComponent(0.58)

    let profilesHeader = NSStackView(views: [profilesHeaderLabel, NSView(), profilesSummaryLabel])
    profilesHeader.orientation = .horizontal
    profilesHeader.alignment = .centerY

    let profilesSection = NSView()
    profilesSection.translatesAutoresizingMaskIntoConstraints = false
    profilesSection.wantsLayer = true
    profilesSection.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    profilesSection.layer?.cornerRadius = 18

    let profilesScrollView = NSScrollView()
    profilesScrollView.translatesAutoresizingMaskIntoConstraints = false
    profilesScrollView.drawsBackground = false
    profilesScrollView.hasVerticalScroller = true
    profilesScrollView.borderType = .noBorder

    let documentView = NSView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    profilesScrollView.documentView = documentView

    profilesStack.translatesAutoresizingMaskIntoConstraints = false
    profilesStack.orientation = .vertical
    profilesStack.spacing = 10
    documentView.addSubview(profilesStack)

    profilesEmptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
    profilesEmptyLabel.textColor = .white.withAlphaComponent(0.54)

    profilesSection.addSubview(profilesHeader)
    profilesSection.addSubview(profilesScrollView)
    profilesHeader.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      profilesSection.heightAnchor.constraint(equalToConstant: 190),

      profilesHeader.leadingAnchor.constraint(equalTo: profilesSection.leadingAnchor, constant: 16),
      profilesHeader.trailingAnchor.constraint(equalTo: profilesSection.trailingAnchor, constant: -16),
      profilesHeader.topAnchor.constraint(equalTo: profilesSection.topAnchor, constant: 14),

      profilesScrollView.leadingAnchor.constraint(equalTo: profilesSection.leadingAnchor, constant: 12),
      profilesScrollView.trailingAnchor.constraint(equalTo: profilesSection.trailingAnchor, constant: -12),
      profilesScrollView.topAnchor.constraint(equalTo: profilesHeader.bottomAnchor, constant: 12),
      profilesScrollView.bottomAnchor.constraint(equalTo: profilesSection.bottomAnchor, constant: -12),

      profilesStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      profilesStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      profilesStack.topAnchor.constraint(equalTo: documentView.topAnchor),
      profilesStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
      profilesStack.widthAnchor.constraint(equalTo: profilesScrollView.contentView.widthAnchor)
    ])

    footerLabel.font = .systemFont(ofSize: 12, weight: .medium)
    footerLabel.textColor = .white.withAlphaComponent(0.68)
    footerLabel.maximumNumberOfLines = 0
    footerLabel.lineBreakMode = .byWordWrapping

    errorLabel.font = .systemFont(ofSize: 12, weight: .medium)
    errorLabel.textColor = NSColor(red: 1.0, green: 0.84, blue: 0.45, alpha: 1)
    errorLabel.maximumNumberOfLines = 0
    errorLabel.lineBreakMode = .byWordWrapping
    errorLabel.isHidden = true

    content.addArrangedSubview(header)
    content.addArrangedSubview(currentAuthCard)
    content.addArrangedSubview(cards)
    content.addArrangedSubview(profilesSection)
    content.addArrangedSubview(footerLabel)
    content.addArrangedSubview(errorLabel)

    NSLayoutConstraint.activate([
      background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      background.topAnchor.constraint(equalTo: view.topAnchor),
      background.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
      content.topAnchor.constraint(equalTo: background.topAnchor),
      content.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor)
    ])
  }

  @objc
  private func refreshTapped() {
    Task {
      await monitor.refresh(manual: true)
    }
  }

  private func render(state: UsageMonitor.State) {
    updatedLabel.stringValue = state.lastUpdatedLabel
    refreshButton.isEnabled = !state.isRefreshing
    footerLabel.stringValue = state.footerMessage ?? ""
    errorLabel.stringValue = state.errorMessage ?? ""
    errorLabel.isHidden = state.errorMessage == nil
    profilesSummaryLabel.stringValue = "\(state.availableProfileCount) available / \(state.profiles.count) saved"
    renderProfiles(state: state)

    let activeProfile = state.profiles.first(where: { $0.id == state.activeProfileID })
    guard let snapshot = state.snapshot else {
      currentAuthCard.configure(
        title: activeProfile?.displayName ?? "Current auth",
        subtitle: "Syncing",
        status: "Waiting",
        detail: "Fetching the first usage snapshot from the active auth profile.",
        accent: NSColor.white.withAlphaComponent(0.38)
      )
      return
    }

    currentAuthCard.configure(
      title: activeProfile?.displayName ?? "Current auth",
      subtitle: snapshot.planType.uppercased(),
      status: state.availabilityLabel(for: snapshot.rateLimit),
      detail: state.availabilityDetail(for: snapshot.rateLimit),
      accent: Self.currentAuthAccentColor(for: snapshot.rateLimit)
    )

    primaryCard.configure(
      status: state.statusLine(for: snapshot.rateLimit.primaryWindow),
      percent: state.remainingLabel(for: snapshot.rateLimit.primaryWindow),
      reset: state.resetLine(for: snapshot.rateLimit.primaryWindow),
      burn: state.primaryBurnLabel(for: snapshot.rateLimit),
      accent: Self.accentColor(for: snapshot.rateLimit.primaryWindow.remainingPercent)
    )

    if let weeklyWindow = snapshot.rateLimit.secondaryWindow {
      weeklyCard.isHidden = false
      weeklyCard.configure(
        status: state.statusLine(for: weeklyWindow),
        percent: state.remainingLabel(for: weeklyWindow),
        reset: state.resetLine(for: weeklyWindow),
        burn: state.weeklyBurnLabel(for: snapshot.rateLimit),
        accent: Self.accentColor(for: weeklyWindow.remainingPercent)
      )
    } else {
      weeklyCard.isHidden = true
    }

    reviewCard.configure(
      status: state.statusLine(for: snapshot.codeReviewRateLimit.primaryWindow),
      percent: state.remainingLabel(for: snapshot.codeReviewRateLimit.primaryWindow),
      reset: state.resetLine(for: snapshot.codeReviewRateLimit.primaryWindow),
      burn: state.burnLabel(from: state.reviewEstimate),
      accent: Self.accentColor(for: snapshot.codeReviewRateLimit.primaryWindow.remainingPercent)
    )
  }

  private func renderProfiles(state: UsageMonitor.State) {
    profilesStack.arrangedSubviews.forEach { view in
      profilesStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    guard !state.profiles.isEmpty else {
      profilesStack.addArrangedSubview(profilesEmptyLabel)
      return
    }

    for profile in state.profiles {
      let row = AuthProfileRowView()
      let isCurrent = profile.id == state.activeProfileID
      row.configure(
        profile: profile,
        isCurrent: isCurrent,
        isBusy: state.isRefreshing
      ) { [weak self] in
        self?.confirmSwitch(to: profile)
      }
      profilesStack.addArrangedSubview(row)
    }
  }

  private func confirmSwitch(to profile: AuthProfileRecord) {
    let alert = NSAlert()
    alert.messageText = "Switch auth profile?"
    alert.informativeText = "This will replace ~/.codex/auth.json with \(profile.displayName). The current auth file will be backed up automatically."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Switch")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      Task {
        await monitor.switchToProfile(id: profile.id)
      }
    }
  }

  private static func accentColor(for remainingPercent: Double) -> NSColor {
    switch remainingPercent {
    case 60...100:
      return NSColor(red: 0.35, green: 0.81, blue: 0.66, alpha: 1)
    case 26..<60:
      return NSColor(red: 0.96, green: 0.73, blue: 0.25, alpha: 1)
    default:
      return NSColor(red: 0.98, green: 0.45, blue: 0.41, alpha: 1)
    }
  }

  private static func currentAuthAccentColor(for rateLimit: UsageLimit) -> NSColor {
    if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
      return NSColor(red: 0.98, green: 0.45, blue: 0.41, alpha: 1)
    }

    if !rateLimit.allowed || rateLimit.limitReached || rateLimit.primaryWindow.remainingPercent <= 0 {
      return NSColor(red: 0.98, green: 0.45, blue: 0.41, alpha: 1)
    }

    return accentColor(for: rateLimit.primaryWindow.remainingPercent)
  }
}

private final class CurrentAuthCardView: NSView {
  private let titleLabel = NSTextField(labelWithString: "Current auth")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(wrappingLabelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  private let statusContainer = NSView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupUI()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupUI() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    layer?.cornerRadius = 18

    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = .white

    subtitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    subtitleLabel.textColor = .white.withAlphaComponent(0.62)

    detailLabel.font = .systemFont(ofSize: 12, weight: .medium)
    detailLabel.textColor = .white.withAlphaComponent(0.78)
    detailLabel.maximumNumberOfLines = 0

    statusContainer.wantsLayer = true
    statusContainer.layer?.cornerRadius = 10
    statusContainer.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = .systemFont(ofSize: 12, weight: .bold)
    statusLabel.textColor = .white

    let topLeft = NSStackView(views: [titleLabel, subtitleLabel])
    topLeft.orientation = .vertical
    topLeft.spacing = 4

    let statusWrapper = NSView()
    statusWrapper.translatesAutoresizingMaskIntoConstraints = false
    statusWrapper.addSubview(statusContainer)
    statusContainer.addSubview(statusLabel)
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      statusContainer.leadingAnchor.constraint(equalTo: statusWrapper.leadingAnchor),
      statusContainer.trailingAnchor.constraint(equalTo: statusWrapper.trailingAnchor),
      statusContainer.topAnchor.constraint(equalTo: statusWrapper.topAnchor),
      statusContainer.bottomAnchor.constraint(equalTo: statusWrapper.bottomAnchor),
      statusLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 10),
      statusLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -10),
      statusLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 5),
      statusLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor, constant: -5)
    ])

    let top = NSStackView(views: [topLeft, NSView(), statusWrapper])
    top.orientation = .horizontal
    top.alignment = .top

    let content = NSStackView(views: [top, detailLabel])
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 12
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
    ])
  }

  func configure(title: String, subtitle: String, status: String, detail: String, accent: NSColor) {
    titleLabel.stringValue = title
    subtitleLabel.stringValue = subtitle
    statusLabel.stringValue = status.uppercased()
    detailLabel.stringValue = detail
    statusContainer.layer?.backgroundColor = accent.withAlphaComponent(0.24).cgColor
    layer?.borderWidth = 1
    layer?.borderColor = accent.withAlphaComponent(0.34).cgColor
  }
}

private final class AuthProfileRowView: NSView {
  private let titleLabel = NSTextField(labelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")
  private let switchButton = NSButton()
  private let statusDot = NSView()
  private var onSwitch: (() -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupUI()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupUI() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
    layer?.cornerRadius = 14
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.clear.cgColor

    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 4
    statusDot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      statusDot.widthAnchor.constraint(equalToConstant: 8),
      statusDot.heightAnchor.constraint(equalToConstant: 8)
    ])

    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .white

    statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
    statusLabel.textColor = .white.withAlphaComponent(0.72)
    statusLabel.maximumNumberOfLines = 2
    statusLabel.lineBreakMode = .byTruncatingTail

    detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
    detailLabel.textColor = .white.withAlphaComponent(0.5)
    detailLabel.maximumNumberOfLines = 2

    switchButton.bezelStyle = .rounded
    switchButton.target = self
    switchButton.action = #selector(handleSwitch)

    let titleRow = NSStackView(views: [statusDot, titleLabel, NSView(), switchButton])
    titleRow.orientation = .horizontal
    titleRow.alignment = .centerY
    titleRow.spacing = 8

    let content = NSStackView(views: [titleRow, statusLabel, detailLabel])
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 6
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
    ])
  }

  func configure(profile: AuthProfileRecord, isCurrent: Bool, isBusy: Bool, onSwitch: @escaping () -> Void) {
    self.onSwitch = onSwitch
    titleLabel.stringValue = profile.displayName
    statusLabel.stringValue = profile.statusText
    detailLabel.stringValue = profile.detailText
    switchButton.title = isCurrent ? "Current" : "Switch"
    switchButton.isEnabled = !isCurrent && !isBusy
    statusDot.layer?.backgroundColor = statusColor(for: profile).cgColor
    statusLabel.textColor = statusTextColor(for: profile)
    layer?.borderColor = borderColor(for: profile, isCurrent: isCurrent).cgColor
  }

  @objc
  private func handleSwitch() {
    onSwitch?()
  }

  private func statusColor(for profile: AuthProfileRecord) -> NSColor {
    if profile.validationError != nil {
      return NSColor(red: 0.98, green: 0.45, blue: 0.41, alpha: 1)
    }

    if profile.latestUsage?.isBlocked == true {
      return NSColor(red: 0.98, green: 0.45, blue: 0.41, alpha: 1)
    }

    if profile.latestUsage != nil {
      return NSColor(red: 0.35, green: 0.81, blue: 0.66, alpha: 1)
    }

    return NSColor.white.withAlphaComponent(0.32)
  }

  private func statusTextColor(for profile: AuthProfileRecord) -> NSColor {
    if profile.validationError != nil || profile.latestUsage?.isBlocked == true {
      return NSColor(red: 1.0, green: 0.84, blue: 0.45, alpha: 1)
    }

    return .white.withAlphaComponent(0.72)
  }

  private func borderColor(for profile: AuthProfileRecord, isCurrent: Bool) -> NSColor {
    if profile.validationError != nil || profile.latestUsage?.isBlocked == true {
      return NSColor(red: 0.98, green: 0.45, blue: 0.41, alpha: isCurrent ? 0.6 : 0.28)
    }

    if isCurrent {
      return NSColor.white.withAlphaComponent(0.22)
    }

    return .clear
  }
}

private final class LimitCardView: NSView {
  private let titleLabel: NSTextField
  private let statusLabel = NSTextField(labelWithString: "--")
  private let percentLabel = NSTextField(labelWithString: "--")
  private let resetLabel = NSTextField(labelWithString: "--")
  private let burnLabel = NSTextField(wrappingLabelWithString: "--")

  init(title: String) {
    titleLabel = NSTextField(labelWithString: title)
    super.init(frame: .zero)
    setupUI()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupUI() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    layer?.cornerRadius = 18

    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .white.withAlphaComponent(0.66)

    statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    statusLabel.textColor = .white.withAlphaComponent(0.72)

    percentLabel.font = .systemFont(ofSize: 30, weight: .bold)
    percentLabel.textColor = .white

    resetLabel.font = .systemFont(ofSize: 12, weight: .medium)
    resetLabel.textColor = .white.withAlphaComponent(0.58)

    burnLabel.font = .systemFont(ofSize: 12, weight: .medium)
    burnLabel.textColor = .white.withAlphaComponent(0.68)
    burnLabel.maximumNumberOfLines = 0

    let left = NSStackView(views: [titleLabel, statusLabel])
    left.orientation = .vertical
    left.spacing = 4

    let valueBlock = NSStackView(views: [percentLabel, resetLabel])
    valueBlock.orientation = .vertical
    valueBlock.spacing = 6

    let top = NSStackView(views: [left, NSView()])
    top.orientation = .horizontal
    top.alignment = .top

    let content = NSStackView(views: [top, valueBlock, burnLabel])
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 10
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
    ])
  }

  func configure(status: String, percent: String, reset: String, burn: String, accent: NSColor) {
    statusLabel.stringValue = status
    percentLabel.stringValue = percent
    percentLabel.textColor = accent
    statusLabel.textColor = accent.withAlphaComponent(0.92)
    resetLabel.stringValue = reset
    burnLabel.stringValue = burn
  }
}
