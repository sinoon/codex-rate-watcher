import AppKit

private enum SurfacePalette {
  static let windowBackground = NSColor(
    calibratedRed: 0.09,
    green: 0.10,
    blue: 0.12,
    alpha: 1
  )
  static let sectionBackground = NSColor(
    calibratedRed: 0.12,
    green: 0.13,
    blue: 0.16,
    alpha: 1
  )
  static let cardBackground = NSColor(
    calibratedRed: 0.15,
    green: 0.16,
    blue: 0.19,
    alpha: 1
  )
  static let controlBackground = NSColor(
    calibratedRed: 0.18,
    green: 0.19,
    blue: 0.23,
    alpha: 1
  )
  static let border = NSColor(calibratedWhite: 1, alpha: 0.08)
  static let secondaryText = NSColor(calibratedWhite: 1, alpha: 0.72)
  static let tertiaryText = NSColor(calibratedWhite: 1, alpha: 0.58)
  static let mutedText = NSColor(calibratedWhite: 1, alpha: 0.48)
}

final class PopoverViewController: NSViewController {
  private let monitor: UsageMonitor
  private var observerID: UUID?

  private let updatedLabel = NSTextField(labelWithString: "正在等第一次同步")
  private let refreshButton = NSButton()
  private let footerLabel = NSTextField(labelWithString: "")
  private let errorLabel = NSTextField(wrappingLabelWithString: "")
  private let currentAuthCard = CurrentAuthCardView()
  private let recommendationCard = RecommendationCardView()
  private let profilesSummaryLabel = NSTextField(labelWithString: "")
  private let profilesStack = NSStackView()
  private let profilesEmptyLabel = NSTextField(labelWithString: "还没有保存过账号。你切换登录后，这里会自动出现。")

  private let primaryCard = LimitCardView(title: "近 5 小时主额度")
  private let weeklyCard = LimitCardView(title: "本周主额度")
  private let reviewCard = LimitCardView(title: "代码审查额度")

  init(monitor: UsageMonitor) {
    self.monitor = monitor
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 580))
    view.wantsLayer = true
    view.layer?.backgroundColor = SurfacePalette.windowBackground.cgColor
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
    let background = NSView()
    background.translatesAutoresizingMaskIntoConstraints = false
    background.wantsLayer = true
    background.layer?.backgroundColor = SurfacePalette.windowBackground.cgColor
    background.layer?.cornerRadius = 22
    background.layer?.masksToBounds = true
    background.layer?.borderWidth = 1
    background.layer?.borderColor = SurfacePalette.border.cgColor
    view.addSubview(background)

    let content = NSStackView()
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 10
    content.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    background.addSubview(content)

    let header = NSStackView()
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 10

    let iconContainer = NSView()
    iconContainer.wantsLayer = true
    iconContainer.layer?.backgroundColor = SurfacePalette.controlBackground.cgColor
    iconContainer.layer?.cornerRadius = 16
    iconContainer.layer?.borderWidth = 1
    iconContainer.layer?.borderColor = SurfacePalette.border.cgColor
    iconContainer.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      iconContainer.widthAnchor.constraint(equalToConstant: 32),
      iconContainer.heightAnchor.constraint(equalToConstant: 32)
    ])

    let iconView = NSImageView(image: NSImage(systemSymbolName: "speedometer", accessibilityDescription: nil) ?? NSImage())
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.contentTintColor = .white
    iconContainer.addSubview(iconView)
    NSLayoutConstraint.activate([
      iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
    ])

    let titleLabel = NSTextField(labelWithString: "Codex 剩余额度")
    titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
    titleLabel.textColor = .white

    updatedLabel.font = .systemFont(ofSize: 11, weight: .medium)
    updatedLabel.textColor = SurfacePalette.tertiaryText

    let headerText = NSStackView(views: [titleLabel, updatedLabel])
    headerText.orientation = .vertical
    headerText.spacing = 2

    refreshButton.bezelStyle = .texturedRounded
    refreshButton.isBordered = false
    refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
    refreshButton.contentTintColor = .white
    refreshButton.wantsLayer = true
    refreshButton.layer?.backgroundColor = SurfacePalette.controlBackground.cgColor
    refreshButton.layer?.cornerRadius = 10
    refreshButton.layer?.borderWidth = 1
    refreshButton.layer?.borderColor = SurfacePalette.border.cgColor
    refreshButton.translatesAutoresizingMaskIntoConstraints = false
    refreshButton.target = self
    refreshButton.action = #selector(refreshTapped)
    NSLayoutConstraint.activate([
      refreshButton.widthAnchor.constraint(equalToConstant: 28),
      refreshButton.heightAnchor.constraint(equalToConstant: 28)
    ])

    let spacer = NSView()
    header.addArrangedSubview(iconContainer)
    header.addArrangedSubview(headerText)
    header.addArrangedSubview(spacer)
    header.addArrangedSubview(refreshButton)

    let topCardsRow = NSStackView(views: [primaryCard, weeklyCard])
    topCardsRow.orientation = .horizontal
    topCardsRow.alignment = .top
    topCardsRow.distribution = .fillEqually
    topCardsRow.spacing = 10

    let cards = NSStackView(views: [topCardsRow, reviewCard])
    cards.orientation = .vertical
    cards.spacing = 10

    [primaryCard, weeklyCard, reviewCard].forEach { card in
      card.translatesAutoresizingMaskIntoConstraints = false
      card.heightAnchor.constraint(equalToConstant: 126).isActive = true
    }

    let profilesHeaderLabel = NSTextField(labelWithString: "已保存账号")
    profilesHeaderLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    profilesHeaderLabel.textColor = .white

    profilesSummaryLabel.font = .systemFont(ofSize: 11, weight: .medium)
    profilesSummaryLabel.textColor = SurfacePalette.tertiaryText

    let profilesHeader = NSStackView(views: [profilesHeaderLabel, NSView(), profilesSummaryLabel])
    profilesHeader.orientation = .horizontal
    profilesHeader.alignment = .centerY

    let profilesSection = NSView()
    profilesSection.translatesAutoresizingMaskIntoConstraints = false
    profilesSection.wantsLayer = true
    profilesSection.layer?.backgroundColor = SurfacePalette.sectionBackground.cgColor
    profilesSection.layer?.cornerRadius = 16
    profilesSection.layer?.borderWidth = 1
    profilesSection.layer?.borderColor = SurfacePalette.border.cgColor

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
    profilesStack.spacing = 8
    documentView.addSubview(profilesStack)

    profilesEmptyLabel.font = .systemFont(ofSize: 11, weight: .medium)
    profilesEmptyLabel.textColor = SurfacePalette.mutedText

    profilesSection.addSubview(profilesHeader)
    profilesSection.addSubview(profilesScrollView)
    profilesHeader.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      profilesSection.widthAnchor.constraint(equalToConstant: 340),
      profilesSection.heightAnchor.constraint(equalToConstant: 480),

      profilesHeader.leadingAnchor.constraint(equalTo: profilesSection.leadingAnchor, constant: 16),
      profilesHeader.trailingAnchor.constraint(equalTo: profilesSection.trailingAnchor, constant: -16),
      profilesHeader.topAnchor.constraint(equalTo: profilesSection.topAnchor, constant: 12),

      profilesScrollView.leadingAnchor.constraint(equalTo: profilesSection.leadingAnchor, constant: 10),
      profilesScrollView.trailingAnchor.constraint(equalTo: profilesSection.trailingAnchor, constant: -10),
      profilesScrollView.topAnchor.constraint(equalTo: profilesHeader.bottomAnchor, constant: 10),
      profilesScrollView.bottomAnchor.constraint(equalTo: profilesSection.bottomAnchor, constant: -10),

      profilesStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      profilesStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      profilesStack.topAnchor.constraint(equalTo: documentView.topAnchor),
      profilesStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
      profilesStack.widthAnchor.constraint(equalTo: profilesScrollView.contentView.widthAnchor)
    ])

    footerLabel.font = .systemFont(ofSize: 11, weight: .medium)
    footerLabel.textColor = SurfacePalette.secondaryText
    footerLabel.maximumNumberOfLines = 0
    footerLabel.lineBreakMode = .byWordWrapping

    errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
    errorLabel.textColor = NSColor(red: 1.0, green: 0.84, blue: 0.45, alpha: 1)
    errorLabel.maximumNumberOfLines = 0
    errorLabel.lineBreakMode = .byWordWrapping
    errorLabel.isHidden = true

    let leftColumn = NSStackView(views: [currentAuthCard, recommendationCard, cards, footerLabel, errorLabel])
    leftColumn.orientation = .vertical
    leftColumn.spacing = 10

    let body = NSStackView(views: [leftColumn, profilesSection])
    body.orientation = .horizontal
    body.alignment = .top
    body.spacing = 12

    leftColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
    profilesSection.setContentHuggingPriority(.required, for: .horizontal)

    content.addArrangedSubview(header)
    content.addArrangedSubview(body)

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
    profilesSummaryLabel.stringValue = "可用 \(state.availableProfileCount) 个 · 共 \(state.profiles.count) 个"
    renderProfiles(state: state)

    let activeProfile = state.profiles.first(where: { $0.id == state.activeProfileID })
    guard let snapshot = state.snapshot else {
      currentAuthCard.configure(
        title: activeProfile?.displayName ?? "当前账号",
        subtitle: "正在同步",
        status: "稍等一下",
        detail: "我正在读取当前账号的额度信息，第一次打开通常要等几秒。",
        accent: NSColor.white.withAlphaComponent(0.38)
      )
      recommendationCard.configure(
        title: "切换建议",
        headline: state.switchRecommendation.headline,
        detail: state.switchRecommendation.detail,
        accent: Self.recommendationAccentColor(for: state.switchRecommendation.kind),
        actionTitle: nil
      ) { }
      return
    }

    currentAuthCard.configure(
      title: activeProfile?.displayName ?? "当前账号",
      subtitle: "\(Self.planDisplayName(for: snapshot.planType)) 套餐",
      status: state.availabilityLabel(for: snapshot.rateLimit),
      detail: state.availabilityDetail(for: snapshot.rateLimit),
      accent: Self.currentAuthAccentColor(for: snapshot.rateLimit)
    )

    let recommendation = state.switchRecommendation
    recommendationCard.configure(
      title: "切换建议",
      headline: recommendation.headline,
      detail: recommendation.detail,
      accent: Self.recommendationAccentColor(for: recommendation.kind),
      actionTitle: recommendation.recommendedProfileID == nil ? nil : "切到推荐账号"
    ) { [weak self] in
      guard let self,
            let profileID = recommendation.recommendedProfileID,
            let profile = state.profiles.first(where: { $0.id == profileID }) else {
        return
      }
      self.confirmSwitch(to: profile)
    }

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
      let isRecommended = profile.id == state.switchRecommendation.recommendedProfileID
      row.configure(
        profile: profile,
        isCurrent: isCurrent,
        isBusy: state.isRefreshing,
        isRecommended: isRecommended
      ) { [weak self] in
        self?.confirmSwitch(to: profile)
      }
      profilesStack.addArrangedSubview(row)
    }
  }

  private func confirmSwitch(to profile: AuthProfileRecord) {
    let alert = NSAlert()
    alert.messageText = "切换到这个账号吗？"
    alert.informativeText = "我会用 \(profile.displayName) 覆盖当前的 ~/.codex/auth.json，并先自动备份你现在这份登录信息。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "切换")
    alert.addButton(withTitle: "取消")

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

  private static func recommendationAccentColor(for kind: UsageMonitor.SwitchRecommendation.Kind) -> NSColor {
    switch kind {
    case .stay:
      return NSColor(red: 0.35, green: 0.81, blue: 0.66, alpha: 1)
    case .switchNow:
      return NSColor(red: 0.96, green: 0.73, blue: 0.25, alpha: 1)
    case .noAvailable:
      return NSColor(red: 0.98, green: 0.45, blue: 0.41, alpha: 1)
    case .syncing:
      return NSColor.white.withAlphaComponent(0.38)
    }
  }

  private static func planDisplayName(for value: String) -> String {
    switch value.lowercased() {
    case "team":
      return "Team"
    case "plus":
      return "Plus"
    default:
      return value.capitalized
    }
  }
}

private final class CurrentAuthCardView: NSView {
  private let titleLabel = NSTextField(labelWithString: "当前账号")
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
    layer?.backgroundColor = SurfacePalette.cardBackground.cgColor
    layer?.cornerRadius = 16
    layer?.borderWidth = 1
    layer?.borderColor = SurfacePalette.border.cgColor

    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    titleLabel.textColor = .white

    subtitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    subtitleLabel.textColor = SurfacePalette.tertiaryText

    detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
    detailLabel.textColor = SurfacePalette.secondaryText
    detailLabel.maximumNumberOfLines = 2

    statusContainer.wantsLayer = true
    statusContainer.layer?.cornerRadius = 9
    statusContainer.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = .systemFont(ofSize: 11, weight: .bold)
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
      statusLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 9),
      statusLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -9),
      statusLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 4),
      statusLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor, constant: -4)
    ])

    let top = NSStackView(views: [topLeft, NSView(), statusWrapper])
    top.orientation = .horizontal
    top.alignment = .top

    let content = NSStackView(views: [top, detailLabel])
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 10
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
    ])
  }

  func configure(title: String, subtitle: String, status: String, detail: String, accent: NSColor) {
    titleLabel.stringValue = title
    subtitleLabel.stringValue = subtitle
    statusLabel.stringValue = status
    detailLabel.stringValue = detail
    statusContainer.layer?.backgroundColor = accent.withAlphaComponent(0.24).cgColor
    layer?.borderWidth = 1
    layer?.borderColor = accent.withAlphaComponent(0.34).cgColor
  }
}

private final class RecommendationCardView: NSView {
  private let titleLabel = NSTextField(labelWithString: "切换建议")
  private let headlineLabel = NSTextField(wrappingLabelWithString: "")
  private let detailLabel = NSTextField(wrappingLabelWithString: "")
  private let actionButton = NSButton()
  private var onAction: (() -> Void)?

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
    layer?.backgroundColor = SurfacePalette.cardBackground.cgColor
    layer?.cornerRadius = 16
    layer?.borderWidth = 1
    layer?.borderColor = SurfacePalette.border.cgColor

    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = SurfacePalette.tertiaryText

    headlineLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    headlineLabel.textColor = .white
    headlineLabel.maximumNumberOfLines = 2

    detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
    detailLabel.textColor = SurfacePalette.secondaryText
    detailLabel.maximumNumberOfLines = 3

    actionButton.bezelStyle = .rounded
    actionButton.font = .systemFont(ofSize: 11, weight: .semibold)
    actionButton.target = self
    actionButton.action = #selector(handleAction)
    actionButton.isHidden = true

    let header = NSStackView(views: [titleLabel, NSView(), actionButton])
    header.orientation = .horizontal
    header.alignment = .centerY

    let content = NSStackView(views: [header, headlineLabel, detailLabel])
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 8
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
    ])
  }

  func configure(
    title: String,
    headline: String,
    detail: String,
    accent: NSColor,
    actionTitle: String?,
    onAction: @escaping () -> Void
  ) {
    self.onAction = onAction
    titleLabel.stringValue = title
    headlineLabel.stringValue = headline
    detailLabel.stringValue = detail
    layer?.borderWidth = 1
    layer?.borderColor = accent.withAlphaComponent(0.34).cgColor

    if let actionTitle {
      actionButton.title = actionTitle
      actionButton.isHidden = false
      actionButton.isEnabled = true
    } else {
      actionButton.title = ""
      actionButton.isHidden = true
      actionButton.isEnabled = false
    }
  }

  @objc
  private func handleAction() {
    onAction?()
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
    layer?.backgroundColor = SurfacePalette.cardBackground.cgColor
    layer?.cornerRadius = 12
    layer?.borderWidth = 1
    layer?.borderColor = SurfacePalette.border.cgColor

    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 4
    statusDot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      statusDot.widthAnchor.constraint(equalToConstant: 8),
      statusDot.heightAnchor.constraint(equalToConstant: 8)
    ])

    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = .white

    statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
    statusLabel.textColor = SurfacePalette.secondaryText
    statusLabel.maximumNumberOfLines = 1
    statusLabel.lineBreakMode = .byTruncatingTail

    detailLabel.font = .systemFont(ofSize: 10, weight: .medium)
    detailLabel.textColor = SurfacePalette.mutedText
    detailLabel.maximumNumberOfLines = 1

    switchButton.bezelStyle = .rounded
    switchButton.font = .systemFont(ofSize: 11, weight: .semibold)
    switchButton.target = self
    switchButton.action = #selector(handleSwitch)

    let titleRow = NSStackView(views: [statusDot, titleLabel, NSView(), switchButton])
    titleRow.orientation = .horizontal
    titleRow.alignment = .centerY
    titleRow.spacing = 8

    let content = NSStackView(views: [titleRow, statusLabel, detailLabel])
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 4
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
    ])
  }

  func configure(
    profile: AuthProfileRecord,
    isCurrent: Bool,
    isBusy: Bool,
    isRecommended: Bool,
    onSwitch: @escaping () -> Void
  ) {
    self.onSwitch = onSwitch
    titleLabel.stringValue = profile.displayName
    statusLabel.stringValue = profile.statusText
    detailLabel.stringValue = profile.detailText
    switchButton.title = isCurrent ? "当前" : (isRecommended ? "推荐切换" : "切换")
    switchButton.isEnabled = !isCurrent && !isBusy
    statusDot.layer?.backgroundColor = statusColor(for: profile).cgColor
    statusLabel.textColor = statusTextColor(for: profile)
    layer?.borderColor = borderColor(for: profile, isCurrent: isCurrent, isRecommended: isRecommended).cgColor
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

    return SurfacePalette.mutedText
  }

  private func statusTextColor(for profile: AuthProfileRecord) -> NSColor {
    if profile.validationError != nil || profile.latestUsage?.isBlocked == true {
      return NSColor(red: 1.0, green: 0.84, blue: 0.45, alpha: 1)
    }

    return SurfacePalette.secondaryText
  }

  private func borderColor(for profile: AuthProfileRecord, isCurrent: Bool, isRecommended: Bool) -> NSColor {
    if profile.validationError != nil || profile.latestUsage?.isBlocked == true {
      return NSColor(red: 0.98, green: 0.45, blue: 0.41, alpha: isCurrent ? 0.6 : 0.28)
    }

    if isCurrent {
      return NSColor(red: 0.35, green: 0.81, blue: 0.66, alpha: 0.42)
    }

    if isRecommended {
      return NSColor(red: 0.96, green: 0.73, blue: 0.25, alpha: 0.42)
    }

    return SurfacePalette.border
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
    layer?.backgroundColor = SurfacePalette.cardBackground.cgColor
    layer?.cornerRadius = 16
    layer?.borderWidth = 1
    layer?.borderColor = SurfacePalette.border.cgColor

    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = SurfacePalette.tertiaryText

    statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    statusLabel.textColor = SurfacePalette.secondaryText

    percentLabel.font = .systemFont(ofSize: 26, weight: .bold)
    percentLabel.textColor = .white

    resetLabel.font = .systemFont(ofSize: 11, weight: .medium)
    resetLabel.textColor = SurfacePalette.tertiaryText

    burnLabel.font = .systemFont(ofSize: 11, weight: .medium)
    burnLabel.textColor = SurfacePalette.secondaryText
    burnLabel.maximumNumberOfLines = 2

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
    content.spacing = 8
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
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
