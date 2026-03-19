import AppKit

// MARK: - Design Tokens

private enum SurfacePalette {
  static let windowBackground = NSColor(
    calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1
  )
  static let sectionBackground = NSColor(
    calibratedRed: 0.10, green: 0.10, blue: 0.13, alpha: 1
  )
  static let cardBackground = NSColor(
    calibratedRed: 0.13, green: 0.13, blue: 0.17, alpha: 1
  )
  static let cardBackgroundHover = NSColor(
    calibratedRed: 0.16, green: 0.16, blue: 0.20, alpha: 1
  )
  static let controlBackground = NSColor(
    calibratedRed: 0.18, green: 0.18, blue: 0.23, alpha: 1
  )
  static let border = NSColor(calibratedWhite: 1, alpha: 0.06)
  static let borderActive = NSColor(calibratedWhite: 1, alpha: 0.12)
  static let primaryText = NSColor(calibratedWhite: 1, alpha: 0.95)
  static let secondaryText = NSColor(calibratedWhite: 1, alpha: 0.68)
  static let tertiaryText = NSColor(calibratedWhite: 1, alpha: 0.48)
  static let mutedText = NSColor(calibratedWhite: 1, alpha: 0.32)

  static let accentGreen = NSColor(
    calibratedRed: 0.30, green: 0.85, blue: 0.65, alpha: 1
  )
  static let accentYellow = NSColor(
    calibratedRed: 1.00, green: 0.78, blue: 0.28, alpha: 1
  )
  static let accentRed = NSColor(
    calibratedRed: 1.00, green: 0.42, blue: 0.38, alpha: 1
  )
}

// MARK: - PopoverViewController

final class PopoverViewController: NSViewController {
  private let monitor: UsageMonitor
  private var observerID: UUID?

  // Header
  private let updatedLabel = NSTextField(labelWithString: "正在等第一次同步")
  private let refreshButton = NSButton()

  // Footer
  private let footerLabel = NSTextField(labelWithString: "")
  private let errorLabel = NSTextField(wrappingLabelWithString: "")

  // Cards
  private let currentAuthCard = CurrentAuthCardView()
  private let recommendationCard = RecommendationCardView()
  private let primaryCard = LimitCardView(title: "近 5 小时主额度")
  private let weeklyCard = LimitCardView(title: "本周主额度")
  private let reviewCard = LimitCardView(title: "代码审查额度")

  // Profiles
  private let profilesSummaryLabel = NSTextField(labelWithString: "")
  private let profilesStack = NSStackView()
  private let profilesEmptyLabel = NSTextField(labelWithString: "还没有保存过账号。你切换登录后，这里会自动出现。")

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

  // MARK: - UI Setup

  private func setupUI() {
    // Outer rounded container
    let background = NSView()
    background.translatesAutoresizingMaskIntoConstraints = false
    background.wantsLayer = true
    background.layer?.backgroundColor = SurfacePalette.windowBackground.cgColor
    background.layer?.cornerRadius = 22
    background.layer?.masksToBounds = true
    background.layer?.borderWidth = 1
    background.layer?.borderColor = SurfacePalette.border.cgColor
    view.addSubview(background)

    // Main content stack
    let content = NSStackView()
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 16
    content.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    background.addSubview(content)

    // --- Header ---
    let header = buildHeader()

    // --- Limit Cards Row ---
    let topCardsRow = NSStackView(views: [primaryCard, weeklyCard])
    topCardsRow.orientation = .horizontal
    topCardsRow.alignment = .top
    topCardsRow.distribution = .fillEqually
    topCardsRow.spacing = 12

    let cardsStack = NSStackView(views: [topCardsRow, reviewCard])
    cardsStack.orientation = .vertical
    cardsStack.spacing = 12

    [primaryCard, weeklyCard, reviewCard].forEach { card in
      card.translatesAutoresizingMaskIntoConstraints = false
      card.heightAnchor.constraint(equalToConstant: 138).isActive = true
    }

    // --- Footer labels ---
    footerLabel.font = .systemFont(ofSize: 11, weight: .medium)
    footerLabel.textColor = SurfacePalette.secondaryText
    footerLabel.maximumNumberOfLines = 0
    footerLabel.lineBreakMode = .byWordWrapping

    errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
    errorLabel.textColor = SurfacePalette.accentYellow
    errorLabel.maximumNumberOfLines = 0
    errorLabel.lineBreakMode = .byWordWrapping
    errorLabel.isHidden = true

    // --- Left Column ---
    let leftColumn = NSStackView(views: [
      currentAuthCard, recommendationCard, cardsStack, footerLabel, errorLabel
    ])
    leftColumn.orientation = .vertical
    leftColumn.spacing = 12

    // --- Profile Section (right panel) ---
    let profilesSection = buildProfilesSection()

    // --- Body (horizontal split) ---
    let body = NSStackView(views: [leftColumn, profilesSection])
    body.orientation = .horizontal
    body.alignment = .top
    body.spacing = 16

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
      content.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor),
    ])
  }

  private func buildHeader() -> NSStackView {
    // Icon container with gradient-like background
    let iconContainer = NSView()
    iconContainer.wantsLayer = true
    iconContainer.layer?.cornerRadius = 10
    iconContainer.layer?.borderWidth = 1
    iconContainer.layer?.borderColor = SurfacePalette.borderActive.cgColor
    iconContainer.translatesAutoresizingMaskIntoConstraints = false

    iconContainer.layer?.backgroundColor = NSColor(
      calibratedRed: 0.12, green: 0.16, blue: 0.22, alpha: 1
    ).cgColor

    NSLayoutConstraint.activate([
      iconContainer.widthAnchor.constraint(equalToConstant: 34),
      iconContainer.heightAnchor.constraint(equalToConstant: 34),
    ])

    let iconView = NSImageView(
      image: NSImage(
        systemSymbolName: "speedometer",
        accessibilityDescription: nil
      ) ?? NSImage()
    )
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.contentTintColor = .white
    let iconConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
    iconView.symbolConfiguration = iconConfig
    iconContainer.addSubview(iconView)
    NSLayoutConstraint.activate([
      iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
    ])

    let titleLabel = NSTextField(labelWithString: "Codex 额度")
    titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
    titleLabel.textColor = SurfacePalette.primaryText

    updatedLabel.font = .systemFont(ofSize: 11, weight: .medium)
    updatedLabel.textColor = SurfacePalette.tertiaryText

    let headerText = NSStackView(views: [titleLabel, updatedLabel])
    headerText.orientation = .vertical
    headerText.spacing = 2
    headerText.alignment = .leading

    // Circular refresh button
    refreshButton.bezelStyle = .texturedRounded
    refreshButton.isBordered = false
    refreshButton.image = NSImage(
      systemSymbolName: "arrow.clockwise",
      accessibilityDescription: "刷新"
    )
    refreshButton.contentTintColor = SurfacePalette.primaryText
    refreshButton.wantsLayer = true
    refreshButton.layer?.backgroundColor = SurfacePalette.controlBackground.cgColor
    refreshButton.layer?.cornerRadius = 15
    refreshButton.layer?.borderWidth = 1
    refreshButton.layer?.borderColor = SurfacePalette.border.cgColor
    refreshButton.translatesAutoresizingMaskIntoConstraints = false
    refreshButton.target = self
    refreshButton.action = #selector(refreshTapped)
    NSLayoutConstraint.activate([
      refreshButton.widthAnchor.constraint(equalToConstant: 30),
      refreshButton.heightAnchor.constraint(equalToConstant: 30),
    ])

    let spacer = NSView()
    let header = NSStackView(views: [iconContainer, headerText, spacer, refreshButton])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 10
    return header
  }

  private func buildProfilesSection() -> NSView {
    let profilesHeaderLabel = NSTextField(labelWithString: "已保存账号")
    profilesHeaderLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    profilesHeaderLabel.textColor = SurfacePalette.primaryText

    profilesSummaryLabel.font = .systemFont(ofSize: 11, weight: .medium)
    profilesSummaryLabel.textColor = SurfacePalette.tertiaryText

    // Count badge
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
    profilesScrollView.scrollerStyle = .overlay

    let documentView = NSView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    profilesScrollView.documentView = documentView

    profilesStack.translatesAutoresizingMaskIntoConstraints = false
    profilesStack.orientation = .vertical
    profilesStack.spacing = 8
    documentView.addSubview(profilesStack)

    profilesEmptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
    profilesEmptyLabel.textColor = SurfacePalette.mutedText
    profilesEmptyLabel.alignment = .center

    profilesSection.addSubview(profilesHeader)
    profilesSection.addSubview(profilesScrollView)
    profilesHeader.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      profilesSection.widthAnchor.constraint(equalToConstant: 340),
      profilesSection.heightAnchor.constraint(equalToConstant: 480),

      profilesHeader.leadingAnchor.constraint(
        equalTo: profilesSection.leadingAnchor, constant: 16
      ),
      profilesHeader.trailingAnchor.constraint(
        equalTo: profilesSection.trailingAnchor, constant: -16
      ),
      profilesHeader.topAnchor.constraint(equalTo: profilesSection.topAnchor, constant: 14),

      profilesScrollView.leadingAnchor.constraint(
        equalTo: profilesSection.leadingAnchor, constant: 10
      ),
      profilesScrollView.trailingAnchor.constraint(
        equalTo: profilesSection.trailingAnchor, constant: -10
      ),
      profilesScrollView.topAnchor.constraint(
        equalTo: profilesHeader.bottomAnchor, constant: 12
      ),
      profilesScrollView.bottomAnchor.constraint(
        equalTo: profilesSection.bottomAnchor, constant: -10
      ),

      profilesStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      profilesStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      profilesStack.topAnchor.constraint(equalTo: documentView.topAnchor),
      profilesStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
      profilesStack.widthAnchor.constraint(equalTo: profilesScrollView.contentView.widthAnchor),
    ])

    return profilesSection
  }

  // MARK: - Actions

  @objc
  private func refreshTapped() {
    Task {
      await monitor.refresh(manual: true)
    }
  }

  // MARK: - Render

  private func render(state: UsageMonitor.State) {
    updatedLabel.stringValue = state.lastUpdatedLabel
    refreshButton.isEnabled = !state.isRefreshing
    footerLabel.stringValue = state.footerMessage ?? ""
    errorLabel.stringValue = state.errorMessage ?? ""
    errorLabel.isHidden = state.errorMessage == nil
    profilesSummaryLabel.stringValue =
      "可用 \(state.availableProfileCount) 个 · 共 \(state.profiles.count) 个"
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
      ) {}
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
        let profile = state.profiles.first(where: { $0.id == profileID })
      else {
        return
      }
      self.confirmSwitch(to: profile)
    }

    primaryCard.configure(
      status: state.statusLine(for: snapshot.rateLimit.primaryWindow),
      percent: state.remainingLabel(for: snapshot.rateLimit.primaryWindow),
      reset: state.resetLine(for: snapshot.rateLimit.primaryWindow),
      burn: state.primaryBurnLabel(for: snapshot.rateLimit),
      accent: Self.accentColor(for: snapshot.rateLimit.primaryWindow.remainingPercent),
      remainingPercent: snapshot.rateLimit.primaryWindow.remainingPercent
    )

    if let weeklyWindow = snapshot.rateLimit.secondaryWindow {
      weeklyCard.isHidden = false
      weeklyCard.configure(
        status: state.statusLine(for: weeklyWindow),
        percent: state.remainingLabel(for: weeklyWindow),
        reset: state.resetLine(for: weeklyWindow),
        burn: state.weeklyBurnLabel(for: snapshot.rateLimit),
        accent: Self.accentColor(for: weeklyWindow.remainingPercent),
        remainingPercent: weeklyWindow.remainingPercent
      )
    } else {
      weeklyCard.isHidden = true
    }

    reviewCard.configure(
      status: state.statusLine(for: snapshot.codeReviewRateLimit.primaryWindow),
      percent: state.remainingLabel(for: snapshot.codeReviewRateLimit.primaryWindow),
      reset: state.resetLine(for: snapshot.codeReviewRateLimit.primaryWindow),
      burn: state.burnLabel(from: state.reviewEstimate),
      accent: Self.accentColor(for: snapshot.codeReviewRateLimit.primaryWindow.remainingPercent),
      remainingPercent: snapshot.codeReviewRateLimit.primaryWindow.remainingPercent
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
    alert.informativeText =
      "我会用 \(profile.displayName) 覆盖当前的 ~/.codex/auth.json，并先自动备份你现在这份登录信息。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "切换")
    alert.addButton(withTitle: "取消")

    if alert.runModal() == .alertFirstButtonReturn {
      Task {
        await monitor.switchToProfile(id: profile.id)
      }
    }
  }

  // MARK: - Static Helpers

  private static func accentColor(for remainingPercent: Double) -> NSColor {
    switch remainingPercent {
    case 60...100:
      return SurfacePalette.accentGreen
    case 26..<60:
      return SurfacePalette.accentYellow
    default:
      return SurfacePalette.accentRed
    }
  }

  private static func currentAuthAccentColor(for rateLimit: UsageLimit) -> NSColor {
    if let weeklyWindow = rateLimit.secondaryWindow, weeklyWindow.remainingPercent <= 0 {
      return SurfacePalette.accentRed
    }

    if !rateLimit.allowed || rateLimit.limitReached
      || rateLimit.primaryWindow.remainingPercent <= 0
    {
      return SurfacePalette.accentRed
    }

    return accentColor(for: rateLimit.primaryWindow.remainingPercent)
  }

  private static func recommendationAccentColor(
    for kind: UsageMonitor.SwitchRecommendation.Kind
  ) -> NSColor {
    switch kind {
    case .stay:
      return SurfacePalette.accentGreen
    case .switchNow:
      return SurfacePalette.accentYellow
    case .noAvailable:
      return SurfacePalette.accentRed
    case .syncing:
      return NSColor.white.withAlphaComponent(0.38)
    }
  }

  static func planDisplayName(for value: String) -> String {
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

// MARK: - CurrentAuthCardView

private final class CurrentAuthCardView: NSView {
  private let accentStripe = NSView()
  private let statusDot = NSView()
  private let titleLabel = NSTextField(labelWithString: "当前账号")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(wrappingLabelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  private let statusPill = NSView()

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
    layer?.cornerRadius = 14
    layer?.borderWidth = 1
    layer?.borderColor = SurfacePalette.border.cgColor

    // Left accent stripe
    accentStripe.wantsLayer = true
    accentStripe.layer?.cornerRadius = 1.5
    accentStripe.translatesAutoresizingMaskIntoConstraints = false
    addSubview(accentStripe)

    // Status dot
    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 6
    statusDot.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    titleLabel.textColor = SurfacePalette.primaryText

    subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
    subtitleLabel.textColor = SurfacePalette.tertiaryText

    detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
    detailLabel.textColor = SurfacePalette.secondaryText
    detailLabel.maximumNumberOfLines = 2
    detailLabel.lineBreakMode = .byWordWrapping

    // Status pill
    statusPill.wantsLayer = true
    statusPill.layer?.cornerRadius = 10
    statusPill.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = .systemFont(ofSize: 11, weight: .bold)
    statusLabel.textColor = SurfacePalette.primaryText
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    statusPill.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      statusLabel.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 10),
      statusLabel.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -10),
      statusLabel.topAnchor.constraint(equalTo: statusPill.topAnchor, constant: 4),
      statusLabel.bottomAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: -4),
    ])

    // Left side: dot + title stack
    let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
    titleStack.orientation = .vertical
    titleStack.spacing = 3
    titleStack.alignment = .leading

    let leftSide = NSStackView(views: [statusDot, titleStack])
    leftSide.orientation = .horizontal
    leftSide.alignment = .centerY
    leftSide.spacing = 8

    NSLayoutConstraint.activate([
      statusDot.widthAnchor.constraint(equalToConstant: 12),
      statusDot.heightAnchor.constraint(equalToConstant: 12),
    ])

    let topRow = NSStackView(views: [leftSide, NSView(), statusPill])
    topRow.orientation = .horizontal
    topRow.alignment = .centerY

    let contentStack = NSStackView(views: [topRow, detailLabel])
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.orientation = .vertical
    contentStack.spacing = 10
    addSubview(contentStack)

    NSLayoutConstraint.activate([
      accentStripe.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
      accentStripe.widthAnchor.constraint(equalToConstant: 3),
      accentStripe.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      accentStripe.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

      contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
    ])
  }

  func configure(
    title: String, subtitle: String, status: String, detail: String, accent: NSColor
  ) {
    titleLabel.stringValue = title
    subtitleLabel.stringValue = subtitle
    statusLabel.stringValue = status
    detailLabel.stringValue = detail
    statusDot.layer?.backgroundColor = accent.cgColor
    statusDot.layer?.shadowColor = accent.cgColor
    statusDot.layer?.shadowRadius = 4
    statusDot.layer?.shadowOpacity = 0.6
    statusDot.layer?.shadowOffset = .zero
    statusPill.layer?.backgroundColor = accent.withAlphaComponent(0.20).cgColor
    accentStripe.layer?.backgroundColor = accent.cgColor
    layer?.borderColor = accent.withAlphaComponent(0.15).cgColor
  }
}

// MARK: - RecommendationCardView

private final class RecommendationCardView: NSView {
  private let tagLabel = NSTextField(labelWithString: "切换建议")
  private let tagPill = NSView()
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
    layer?.cornerRadius = 14
    layer?.borderWidth = 1
    layer?.borderColor = SurfacePalette.border.cgColor

    // Tag pill
    tagPill.wantsLayer = true
    tagPill.layer?.cornerRadius = 8
    tagPill.layer?.backgroundColor = SurfacePalette.controlBackground.cgColor
    tagPill.translatesAutoresizingMaskIntoConstraints = false

    tagLabel.font = .systemFont(ofSize: 10, weight: .semibold)
    tagLabel.textColor = SurfacePalette.tertiaryText
    tagLabel.translatesAutoresizingMaskIntoConstraints = false
    tagPill.addSubview(tagLabel)
    NSLayoutConstraint.activate([
      tagLabel.leadingAnchor.constraint(equalTo: tagPill.leadingAnchor, constant: 8),
      tagLabel.trailingAnchor.constraint(equalTo: tagPill.trailingAnchor, constant: -8),
      tagLabel.topAnchor.constraint(equalTo: tagPill.topAnchor, constant: 3),
      tagLabel.bottomAnchor.constraint(equalTo: tagPill.bottomAnchor, constant: -3),
    ])

    headlineLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    headlineLabel.textColor = SurfacePalette.primaryText
    headlineLabel.maximumNumberOfLines = 2
    headlineLabel.lineBreakMode = .byWordWrapping

    detailLabel.font = .systemFont(ofSize: 12, weight: .medium)
    detailLabel.textColor = SurfacePalette.secondaryText
    detailLabel.maximumNumberOfLines = 3
    detailLabel.lineBreakMode = .byWordWrapping

    // Pill-shaped action button
    actionButton.bezelStyle = .texturedRounded
    actionButton.isBordered = false
    actionButton.wantsLayer = true
    actionButton.layer?.cornerRadius = 12
    actionButton.font = .systemFont(ofSize: 12, weight: .semibold)
    actionButton.contentTintColor = SurfacePalette.windowBackground
    actionButton.target = self
    actionButton.action = #selector(handleAction)
    actionButton.isHidden = true
    actionButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      actionButton.heightAnchor.constraint(equalToConstant: 26),
    ])

    let tagRow = NSStackView(views: [tagPill, NSView()])
    tagRow.orientation = .horizontal

    let buttonRow = NSStackView(views: [NSView(), actionButton])
    buttonRow.orientation = .horizontal

    let content = NSStackView(views: [tagRow, headlineLabel, detailLabel, buttonRow])
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 8
    content.alignment = .leading
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
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
    tagLabel.stringValue = title
    headlineLabel.stringValue = headline
    detailLabel.stringValue = detail
    layer?.borderColor = accent.withAlphaComponent(0.15).cgColor

    if let actionTitle {
      actionButton.title = "  \(actionTitle)  "
      actionButton.layer?.backgroundColor = accent.cgColor
      actionButton.contentTintColor = SurfacePalette.windowBackground
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

// MARK: - AuthProfileRowView

private final class AuthProfileRowView: NSView {
  private let accentStripe = NSView()
  private let statusDot = NSView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")
  private let switchButton = NSButton()
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

    // Left accent stripe
    accentStripe.wantsLayer = true
    accentStripe.layer?.cornerRadius = 1.5
    accentStripe.translatesAutoresizingMaskIntoConstraints = false
    addSubview(accentStripe)

    // Status dot with glow
    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 4
    statusDot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      statusDot.widthAnchor.constraint(equalToConstant: 8),
      statusDot.heightAnchor.constraint(equalToConstant: 8),
    ])

    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = SurfacePalette.primaryText
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.maximumNumberOfLines = 1

    statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
    statusLabel.textColor = SurfacePalette.secondaryText
    statusLabel.maximumNumberOfLines = 1
    statusLabel.lineBreakMode = .byTruncatingTail

    detailLabel.font = .systemFont(ofSize: 10, weight: .medium)
    detailLabel.textColor = SurfacePalette.mutedText
    detailLabel.maximumNumberOfLines = 1
    detailLabel.lineBreakMode = .byTruncatingTail

    // Switch button styled as pill
    switchButton.bezelStyle = .texturedRounded
    switchButton.isBordered = false
    switchButton.wantsLayer = true
    switchButton.layer?.cornerRadius = 10
    switchButton.layer?.backgroundColor = SurfacePalette.controlBackground.cgColor
    switchButton.layer?.borderWidth = 1
    switchButton.layer?.borderColor = SurfacePalette.border.cgColor
    switchButton.font = .systemFont(ofSize: 11, weight: .semibold)
    switchButton.contentTintColor = SurfacePalette.primaryText
    switchButton.target = self
    switchButton.action = #selector(handleSwitch)
    switchButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      switchButton.heightAnchor.constraint(equalToConstant: 22),
    ])

    let titleRow = NSStackView(views: [statusDot, titleLabel, NSView(), switchButton])
    titleRow.orientation = .horizontal
    titleRow.alignment = .centerY
    titleRow.spacing = 8

    let content = NSStackView(views: [titleRow, statusLabel, detailLabel])
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 4
    content.alignment = .leading
    addSubview(content)

    NSLayoutConstraint.activate([
      accentStripe.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
      accentStripe.widthAnchor.constraint(equalToConstant: 3),
      accentStripe.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      accentStripe.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
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

    let dotColor = statusColor(for: profile)
    statusDot.layer?.backgroundColor = dotColor.cgColor
    statusDot.layer?.shadowColor = dotColor.cgColor
    statusDot.layer?.shadowRadius = 3
    statusDot.layer?.shadowOpacity = 0.5
    statusDot.layer?.shadowOffset = .zero

    statusLabel.textColor = statusTextColor(for: profile)

    // Button styling
    if isCurrent {
      switchButton.title = " 当前 "
      switchButton.isEnabled = false
      switchButton.layer?.backgroundColor = SurfacePalette.accentGreen.withAlphaComponent(0.15)
        .cgColor
      switchButton.contentTintColor = SurfacePalette.accentGreen
      switchButton.layer?.borderColor = SurfacePalette.accentGreen.withAlphaComponent(0.25).cgColor
    } else if isRecommended {
      switchButton.title = " 推荐切换 "
      switchButton.isEnabled = !isBusy
      switchButton.layer?.backgroundColor = SurfacePalette.accentYellow.withAlphaComponent(0.15)
        .cgColor
      switchButton.contentTintColor = SurfacePalette.accentYellow
      switchButton.layer?.borderColor = SurfacePalette.accentYellow.withAlphaComponent(0.25)
        .cgColor
    } else {
      switchButton.title = " 切换 "
      switchButton.isEnabled = !isBusy
      switchButton.layer?.backgroundColor = SurfacePalette.controlBackground.cgColor
      switchButton.contentTintColor = SurfacePalette.primaryText
      switchButton.layer?.borderColor = SurfacePalette.border.cgColor
    }

    // Accent stripe + card background
    let isError = profile.validationError != nil || profile.latestUsage?.isBlocked == true
    if isError {
      accentStripe.layer?.backgroundColor = SurfacePalette.accentRed.cgColor
      accentStripe.isHidden = false
      layer?.backgroundColor =
        SurfacePalette.accentRed.withAlphaComponent(0.05).blended(
          withFraction: 0.95, of: SurfacePalette.cardBackground
        )?.cgColor ?? SurfacePalette.cardBackground.cgColor
    } else if isCurrent {
      accentStripe.layer?.backgroundColor = SurfacePalette.accentGreen.cgColor
      accentStripe.isHidden = false
      layer?.backgroundColor = SurfacePalette.cardBackground.cgColor
    } else if isRecommended {
      accentStripe.layer?.backgroundColor = SurfacePalette.accentYellow.cgColor
      accentStripe.isHidden = false
      layer?.backgroundColor = SurfacePalette.cardBackground.cgColor
    } else {
      accentStripe.isHidden = true
      layer?.backgroundColor = SurfacePalette.cardBackground.cgColor
    }

    layer?.borderColor = borderColor(
      for: profile, isCurrent: isCurrent, isRecommended: isRecommended
    ).cgColor
  }

  @objc
  private func handleSwitch() {
    onSwitch?()
  }

  private func statusColor(for profile: AuthProfileRecord) -> NSColor {
    if profile.validationError != nil {
      return SurfacePalette.accentRed
    }
    if profile.latestUsage?.isBlocked == true {
      return SurfacePalette.accentRed
    }
    if profile.latestUsage != nil {
      return SurfacePalette.accentGreen
    }
    return SurfacePalette.mutedText
  }

  private func statusTextColor(for profile: AuthProfileRecord) -> NSColor {
    if profile.validationError != nil || profile.latestUsage?.isBlocked == true {
      return SurfacePalette.accentYellow
    }
    return SurfacePalette.secondaryText
  }

  private func borderColor(
    for profile: AuthProfileRecord, isCurrent: Bool, isRecommended: Bool
  ) -> NSColor {
    if profile.validationError != nil || profile.latestUsage?.isBlocked == true {
      return SurfacePalette.accentRed.withAlphaComponent(isCurrent ? 0.40 : 0.20)
    }
    if isCurrent {
      return SurfacePalette.accentGreen.withAlphaComponent(0.30)
    }
    if isRecommended {
      return SurfacePalette.accentYellow.withAlphaComponent(0.30)
    }
    return SurfacePalette.border
  }
}

// MARK: - LimitCardView

private final class LimitCardView: NSView {
  private let titleLabel: NSTextField
  private let statusBadge = NSView()
  private let statusLabel = NSTextField(labelWithString: "--")
  private let percentLabel = NSTextField(labelWithString: "--")
  private let progressTrack = NSView()
  private let progressFill = NSView()
  private let resetLabel = NSTextField(labelWithString: "--")
  private let burnLabel = NSTextField(wrappingLabelWithString: "--")
  private var progressFillWidth: NSLayoutConstraint?
  private var currentAccent: NSColor = SurfacePalette.accentGreen

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
    layer?.cornerRadius = 14
    layer?.borderWidth = 1
    layer?.borderColor = SurfacePalette.border.cgColor

    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = SurfacePalette.tertiaryText

    // Status badge (pill)
    statusBadge.wantsLayer = true
    statusBadge.layer?.cornerRadius = 8
    statusBadge.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = .systemFont(ofSize: 10, weight: .bold)
    statusLabel.textColor = SurfacePalette.primaryText
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusBadge.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      statusLabel.leadingAnchor.constraint(equalTo: statusBadge.leadingAnchor, constant: 8),
      statusLabel.trailingAnchor.constraint(equalTo: statusBadge.trailingAnchor, constant: -8),
      statusLabel.topAnchor.constraint(equalTo: statusBadge.topAnchor, constant: 2),
      statusLabel.bottomAnchor.constraint(equalTo: statusBadge.bottomAnchor, constant: -2),
    ])

    // Percent label — large accent number
    percentLabel.font = .systemFont(ofSize: 28, weight: .bold)
    percentLabel.textColor = SurfacePalette.accentGreen

    // Progress bar
    progressTrack.wantsLayer = true
    progressTrack.layer?.backgroundColor = SurfacePalette.controlBackground.cgColor
    progressTrack.layer?.cornerRadius = 3
    progressTrack.translatesAutoresizingMaskIntoConstraints = false

    progressFill.wantsLayer = true
    progressFill.layer?.cornerRadius = 3
    progressFill.layer?.backgroundColor = SurfacePalette.accentGreen.cgColor
    progressFill.translatesAutoresizingMaskIntoConstraints = false
    progressTrack.addSubview(progressFill)

    let fillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
    progressFillWidth = fillWidth

    NSLayoutConstraint.activate([
      progressTrack.heightAnchor.constraint(equalToConstant: 6),
      progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
      progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
      progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
      fillWidth,
    ])

    resetLabel.font = .systemFont(ofSize: 11, weight: .medium)
    resetLabel.textColor = SurfacePalette.tertiaryText

    burnLabel.font = .systemFont(ofSize: 11, weight: .medium)
    burnLabel.textColor = SurfacePalette.secondaryText
    burnLabel.maximumNumberOfLines = 2
    burnLabel.lineBreakMode = .byWordWrapping

    // Top row: title left, status badge right
    let topRow = NSStackView(views: [titleLabel, NSView(), statusBadge])
    topRow.orientation = .horizontal
    topRow.alignment = .centerY

    // Content stack
    let content = NSStackView(views: [
      topRow, percentLabel, progressTrack, resetLabel, burnLabel,
    ])
    content.translatesAutoresizingMaskIntoConstraints = false
    content.orientation = .vertical
    content.spacing = 6
    content.alignment = .leading
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

      progressTrack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      progressTrack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
    ])
  }

  override func layout() {
    super.layout()
    updateProgressBar()
    updateGlowBorder()
  }

  func configure(
    status: String,
    percent: String,
    reset: String,
    burn: String,
    accent: NSColor,
    remainingPercent: Double = 50
  ) {
    currentAccent = accent
    statusLabel.stringValue = status
    statusBadge.layer?.backgroundColor = accent.withAlphaComponent(0.18).cgColor
    statusLabel.textColor = accent
    percentLabel.stringValue = percent
    percentLabel.textColor = accent
    resetLabel.stringValue = reset
    burnLabel.stringValue = burn
    progressFill.layer?.backgroundColor = accent.cgColor

    // Update progress width based on remaining percent
    let clampedPercent = max(0, min(100, remainingPercent))
    let trackWidth = progressTrack.bounds.width
    if trackWidth > 0 {
      progressFillWidth?.constant = trackWidth * clampedPercent / 100.0
    } else {
      // Schedule layout pass to recalculate
      needsLayout = true
    }

    // Subtle glow border
    updateGlowBorder()
  }

  private func updateProgressBar() {
    let trackWidth = progressTrack.bounds.width
    guard trackWidth > 0 else { return }
    // Re-derive from label text
    let text = percentLabel.stringValue.replacingOccurrences(of: "%", with: "")
    if let value = Double(text) {
      progressFillWidth?.constant = trackWidth * max(0, min(100, value)) / 100.0
    }
  }

  private func updateGlowBorder() {
    layer?.borderColor = currentAccent.withAlphaComponent(0.15).cgColor
  }
}
