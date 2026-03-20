import AppKit
import CodexRateKit

// MARK: - Design Tokens (Linear-inspired)

private enum LN {
  static let bg           = NSColor(srgbRed: 0.047, green: 0.051, blue: 0.063, alpha: 1)
  static let surface      = NSColor(srgbRed: 0.098, green: 0.106, blue: 0.125, alpha: 1)
  static let surfaceHover = NSColor(srgbRed: 0.137, green: 0.145, blue: 0.165, alpha: 1)
  static let elevated     = NSColor(srgbRed: 0.176, green: 0.184, blue: 0.200, alpha: 1)
  static let border       = NSColor(srgbRed: 0.176, green: 0.184, blue: 0.200, alpha: 1)
  static let borderSubtle = NSColor(srgbRed: 0.137, green: 0.145, blue: 0.165, alpha: 1)
  static let textPrimary   = NSColor(srgbRed: 0.933, green: 0.937, blue: 0.941, alpha: 1)
  static let textSecondary = NSColor(srgbRed: 0.541, green: 0.561, blue: 0.596, alpha: 1)
  static let textTertiary  = NSColor(srgbRed: 0.384, green: 0.400, blue: 0.427, alpha: 1)
  static let textMuted     = NSColor(srgbRed: 0.278, green: 0.290, blue: 0.310, alpha: 1)
  static let green  = NSColor(srgbRed: 0.298, green: 0.784, blue: 0.471, alpha: 1)
  static let yellow = NSColor(srgbRed: 0.957, green: 0.737, blue: 0.263, alpha: 1)
  static let red    = NSColor(srgbRed: 0.918, green: 0.345, blue: 0.345, alpha: 1)
  static let blue   = NSColor(srgbRed: 0.357, green: 0.416, blue: 0.816, alpha: 1)

  static let radius:   CGFloat = 10
  static let radiusSm: CGFloat = 6
  static let pad:      CGFloat = 16
  static let cardPad:  CGFloat = 12
  static let gap:      CGFloat = 12
  static let gapSm:    CGFloat = 8
  static let gapXs:    CGFloat = 4

  static let fontHero:    CGFloat = 44
  static let fontTitle:   CGFloat = 15
  static let fontBody:    CGFloat = 13
  static let fontCaption: CGFloat = 12
  static let fontSmall:   CGFloat = 11
  static let fontMicro:   CGFloat = 10

  static let popoverW: CGFloat = 400
  static let progressH: CGFloat = 4
  static let progressR: CGFloat = 2
}

// MARK: - PopoverViewController

final class PopoverViewController: NSViewController {
  private let monitor: UsageMonitor
  private var observerID: UUID?

  // Header
  private let titleLabel    = NSTextField(labelWithString: "Codex Rate Watcher")
  private let updatedLabel  = NSTextField(labelWithString: "")
  private let refreshButton = NSButton()

  // Primary card
  private let statusDot      = NSView()
  private let accountLabel   = NSTextField(labelWithString: "")
  private let statusBadge    = NSView()
  private let statusBadgeLbl = NSTextField(labelWithString: "")
  private let heroNumber     = NSTextField(labelWithString: "--")
  private let heroSuffix     = NSTextField(labelWithString: "%")
  private let heroSubline    = NSTextField(labelWithString: "")
  private let primarySectionLabel = NSTextField(labelWithString: "5h Primary Quota")
  private let primaryTrack   = NSView()
  private let primaryFill    = NSView()
  private var primaryFillW: NSLayoutConstraint?

  // Quota card (weekly + review)
  private let weeklyLabel  = NSTextField(labelWithString: "Weekly")
  private let weeklyPct    = NSTextField(labelWithString: "")
  private let weeklyTrack  = NSView()
  private let weeklyFill   = NSView()
  private var weeklyFillW: NSLayoutConstraint?
  private let weeklyDetail = NSTextField(labelWithString: "")

  private let reviewLabel  = NSTextField(labelWithString: "Review")
  private let reviewPct    = NSTextField(labelWithString: "")
  private let reviewTrack  = NSView()
  private let reviewFill   = NSView()
  private var reviewFillW: NSLayoutConstraint?
  private let reviewDetail = NSTextField(labelWithString: "")

  // Recommendation banner
  private var recWrapper: NSView!
  private let recBanner      = NSView()
  private let recIcon        = NSTextField(labelWithString: "")
  private let recLabel       = NSTextField(labelWithString: "")
  private let recBtn         = NSButton()
  private var recProfileID: UUID?

  // Profile section
  private let profileHeader   = NSTextField(labelWithString: "")
  private let profileStack    = NSStackView()

  // Footer
  private let footerLabel    = NSTextField(labelWithString: "")
  private let errorLabel     = NSTextField(labelWithString: "")

  init(monitor: UsageMonitor) {
    self.monitor = monitor
    super.init(nibName: nil, bundle: nil)
  }
  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    let v = NSView(frame: NSRect(x: 0, y: 0, width: LN.popoverW, height: 10))
    v.wantsLayer = true
    v.layer?.backgroundColor = LN.bg.cgColor
    view = v
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    buildLayout()
    observerID = monitor.addObserver { [weak self] s in
      DispatchQueue.main.async { self?.render(state: s) }
    }
  }

  deinit {
    if let observerID {
      let m = monitor; Task { @MainActor in m.removeObserver(observerID) }
    }
  }

  // MARK: - Build Layout

  private func buildLayout() {
    let root = NSStackView()
    root.orientation = .vertical
    root.spacing = 0
    root.alignment = .leading
    root.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(root)

    NSLayoutConstraint.activate([
      root.topAnchor.constraint(equalTo: view.topAnchor),
      root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      root.widthAnchor.constraint(equalToConstant: LN.popoverW),
    ])

    let headerView = makeHeader()
    let primaryCard = makePrimaryCard()
    let quotaCard = makeQuotaCard()
    let recView = makeRecBanner()
    let profileSection = makeProfileSection()
    let footer = makeFooter()

    root.addArrangedSubview(headerView)
    root.addArrangedSubview(primaryCard)
    root.addArrangedSubview(quotaCard)
    root.addArrangedSubview(recView)
    root.addArrangedSubview(profileSection)
    root.addArrangedSubview(footer)

    root.setCustomSpacing(LN.gap, after: headerView)
    root.setCustomSpacing(LN.gapSm, after: primaryCard)
    root.setCustomSpacing(LN.gap, after: quotaCard)
    root.setCustomSpacing(LN.gap, after: recView)
    root.setCustomSpacing(LN.gapSm, after: profileSection)
  }

  // MARK: - Header

  private func makeHeader() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .systemFont(ofSize: LN.fontTitle, weight: .semibold)
    titleLabel.textColor = LN.textPrimary
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    updatedLabel.font = .systemFont(ofSize: LN.fontMicro, weight: .medium)
    updatedLabel.textColor = LN.textMuted
    updatedLabel.translatesAutoresizingMaskIntoConstraints = false

    refreshButton.bezelStyle = .texturedRounded
    refreshButton.isBordered = false
    refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise",
                                  accessibilityDescription: "Refresh")
    refreshButton.contentTintColor = LN.textTertiary
    refreshButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
    refreshButton.target = self
    refreshButton.action = #selector(refreshTapped)
    refreshButton.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(titleLabel)
    container.addSubview(updatedLabel)
    container.addSubview(refreshButton)

    NSLayoutConstraint.activate([
      container.heightAnchor.constraint(equalToConstant: 40),
      container.widthAnchor.constraint(equalToConstant: LN.popoverW),
      titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: LN.pad),
      titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      updatedLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
      updatedLabel.lastBaselineAnchor.constraint(equalTo: titleLabel.lastBaselineAnchor),
      refreshButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LN.pad),
      refreshButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      refreshButton.widthAnchor.constraint(equalToConstant: 24),
      refreshButton.heightAnchor.constraint(equalToConstant: 24),
    ])

    return container
  }

  // MARK: - Primary Card (hero metric in a card)

  private func makePrimaryCard() -> NSView {
    let wrapper = NSView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false

    let card = NSView()
    card.wantsLayer = true
    card.layer?.backgroundColor = LN.surface.cgColor
    card.layer?.cornerRadius = LN.radius
    card.layer?.borderWidth = 1
    card.layer?.borderColor = LN.borderSubtle.cgColor
    card.translatesAutoresizingMaskIntoConstraints = false

    // Section label
    primarySectionLabel.font = .systemFont(ofSize: LN.fontMicro, weight: .semibold)
    primarySectionLabel.textColor = LN.textMuted
    primarySectionLabel.translatesAutoresizingMaskIntoConstraints = false

    // Status dot + account
    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 3.5
    statusDot.layer?.backgroundColor = LN.textMuted.cgColor
    statusDot.translatesAutoresizingMaskIntoConstraints = false

    accountLabel.font = .systemFont(ofSize: LN.fontSmall, weight: .medium)
    accountLabel.textColor = LN.textSecondary
    accountLabel.lineBreakMode = .byTruncatingTail
    accountLabel.maximumNumberOfLines = 1
    accountLabel.translatesAutoresizingMaskIntoConstraints = false

    // Status badge
    statusBadge.wantsLayer = true
    statusBadge.layer?.cornerRadius = LN.radiusSm
    statusBadge.translatesAutoresizingMaskIntoConstraints = false
    statusBadgeLbl.font = .systemFont(ofSize: LN.fontMicro, weight: .semibold)
    statusBadgeLbl.translatesAutoresizingMaskIntoConstraints = false
    statusBadge.addSubview(statusBadgeLbl)
    NSLayoutConstraint.activate([
      statusBadgeLbl.leadingAnchor.constraint(equalTo: statusBadge.leadingAnchor, constant: 6),
      statusBadgeLbl.trailingAnchor.constraint(equalTo: statusBadge.trailingAnchor, constant: -6),
      statusBadgeLbl.topAnchor.constraint(equalTo: statusBadge.topAnchor, constant: 2),
      statusBadgeLbl.bottomAnchor.constraint(equalTo: statusBadge.bottomAnchor, constant: -2),
    ])

    // Hero number
    heroNumber.font = .monospacedDigitSystemFont(ofSize: LN.fontHero, weight: .bold)
    heroNumber.textColor = LN.green
    heroNumber.translatesAutoresizingMaskIntoConstraints = false

    heroSuffix.font = .systemFont(ofSize: LN.fontCaption, weight: .medium)
    heroSuffix.textColor = LN.green.withAlphaComponent(0.5)
    heroSuffix.translatesAutoresizingMaskIntoConstraints = false

    heroSubline.font = .systemFont(ofSize: LN.fontSmall, weight: .medium)
    heroSubline.textColor = LN.textTertiary
    heroSubline.maximumNumberOfLines = 1
    heroSubline.lineBreakMode = .byTruncatingTail
    heroSubline.translatesAutoresizingMaskIntoConstraints = false

    // Progress bar
    primaryTrack.wantsLayer = true
    primaryTrack.layer?.backgroundColor = LN.elevated.cgColor
    primaryTrack.layer?.cornerRadius = LN.progressR
    primaryTrack.translatesAutoresizingMaskIntoConstraints = false

    primaryFill.wantsLayer = true
    primaryFill.layer?.cornerRadius = LN.progressR
    primaryFill.layer?.backgroundColor = LN.green.cgColor
    primaryFill.translatesAutoresizingMaskIntoConstraints = false
    primaryTrack.addSubview(primaryFill)

    let fw = primaryFill.widthAnchor.constraint(equalToConstant: 0)
    primaryFillW = fw

    card.addSubview(primarySectionLabel)
    card.addSubview(statusDot)
    card.addSubview(accountLabel)
    card.addSubview(statusBadge)
    card.addSubview(heroNumber)
    card.addSubview(heroSuffix)
    card.addSubview(heroSubline)
    card.addSubview(primaryTrack)

    let innerW = LN.popoverW - LN.pad * 2
    let cPad = LN.cardPad

    NSLayoutConstraint.activate([
      // Section label top
      primarySectionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cPad),
      primarySectionLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: cPad),

      // Account row
      statusDot.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cPad),
      statusDot.topAnchor.constraint(equalTo: primarySectionLabel.bottomAnchor, constant: 8),
      statusDot.widthAnchor.constraint(equalToConstant: 7),
      statusDot.heightAnchor.constraint(equalToConstant: 7),

      accountLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 5),
      accountLabel.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),
      accountLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusBadge.leadingAnchor, constant: -8),

      statusBadge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cPad),
      statusBadge.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),

      // Hero
      heroNumber.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cPad),
      heroNumber.topAnchor.constraint(equalTo: statusDot.bottomAnchor, constant: 6),

      heroSuffix.leadingAnchor.constraint(equalTo: heroNumber.trailingAnchor, constant: 2),
      heroSuffix.lastBaselineAnchor.constraint(equalTo: heroNumber.lastBaselineAnchor),

      heroSubline.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cPad),
      heroSubline.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cPad),
      heroSubline.topAnchor.constraint(equalTo: heroNumber.bottomAnchor, constant: -2),

      // Progress bar
      primaryTrack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cPad),
      primaryTrack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cPad),
      primaryTrack.topAnchor.constraint(equalTo: heroSubline.bottomAnchor, constant: 8),
      primaryTrack.heightAnchor.constraint(equalToConstant: LN.progressH),
      primaryTrack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -cPad),

      primaryFill.leadingAnchor.constraint(equalTo: primaryTrack.leadingAnchor),
      primaryFill.topAnchor.constraint(equalTo: primaryTrack.topAnchor),
      primaryFill.bottomAnchor.constraint(equalTo: primaryTrack.bottomAnchor),
      fw,
    ])

    wrapper.addSubview(card)
    NSLayoutConstraint.activate([
      wrapper.widthAnchor.constraint(equalToConstant: LN.popoverW),
      card.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: LN.pad),
      card.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -LN.pad),
      card.topAnchor.constraint(equalTo: wrapper.topAnchor),
      card.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
    ])

    return wrapper
  }

  // MARK: - Quota Card (weekly + review in one card)

  private func makeQuotaCard() -> NSView {
    let wrapper = NSView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false

    let card = NSView()
    card.wantsLayer = true
    card.layer?.backgroundColor = LN.surface.cgColor
    card.layer?.cornerRadius = LN.radius
    card.layer?.borderWidth = 1
    card.layer?.borderColor = LN.borderSubtle.cgColor
    card.translatesAutoresizingMaskIntoConstraints = false

    let sectionLabel = NSTextField(labelWithString: "Other Quotas")
    sectionLabel.font = .systemFont(ofSize: LN.fontMicro, weight: .semibold)
    sectionLabel.textColor = LN.textMuted
    sectionLabel.translatesAutoresizingMaskIntoConstraints = false

    // Weekly row
    configureMetricLabel(weeklyLabel)
    configureMetricPct(weeklyPct)
    configureMetricTrack(weeklyTrack)
    configureMetricFill(weeklyFill, in: weeklyTrack)
    let wfw = weeklyFill.widthAnchor.constraint(equalToConstant: 0)
    weeklyFillW = wfw
    wfw.isActive = true
    configureDetailLabel(weeklyDetail)

    // Review row
    configureMetricLabel(reviewLabel)
    configureMetricPct(reviewPct)
    configureMetricTrack(reviewTrack)
    configureMetricFill(reviewFill, in: reviewTrack)
    let rfw = reviewFill.widthAnchor.constraint(equalToConstant: 0)
    reviewFillW = rfw
    rfw.isActive = true
    configureDetailLabel(reviewDetail)

    // Divider
    let divider = NSView()
    divider.wantsLayer = true
    divider.layer?.backgroundColor = LN.borderSubtle.cgColor
    divider.translatesAutoresizingMaskIntoConstraints = false

    card.addSubview(sectionLabel)
    card.addSubview(weeklyLabel)
    card.addSubview(weeklyPct)
    card.addSubview(weeklyTrack)
    card.addSubview(weeklyDetail)
    card.addSubview(divider)
    card.addSubview(reviewLabel)
    card.addSubview(reviewPct)
    card.addSubview(reviewTrack)
    card.addSubview(reviewDetail)

    let cPad = LN.cardPad
    let trackW: CGFloat = 100

    NSLayoutConstraint.activate([
      sectionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cPad),
      sectionLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: cPad),

      // Weekly row
      weeklyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cPad),
      weeklyLabel.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 8),
      weeklyLabel.widthAnchor.constraint(equalToConstant: 56),

      weeklyPct.leadingAnchor.constraint(equalTo: weeklyLabel.trailingAnchor, constant: 4),
      weeklyPct.centerYAnchor.constraint(equalTo: weeklyLabel.centerYAnchor),
      weeklyPct.widthAnchor.constraint(equalToConstant: 40),

      weeklyTrack.leadingAnchor.constraint(equalTo: weeklyPct.trailingAnchor, constant: 6),
      weeklyTrack.centerYAnchor.constraint(equalTo: weeklyLabel.centerYAnchor),
      weeklyTrack.widthAnchor.constraint(equalToConstant: trackW),
      weeklyTrack.heightAnchor.constraint(equalToConstant: LN.progressH),

      weeklyDetail.leadingAnchor.constraint(equalTo: weeklyTrack.trailingAnchor, constant: 8),
      weeklyDetail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cPad),
      weeklyDetail.centerYAnchor.constraint(equalTo: weeklyLabel.centerYAnchor),

      // Divider
      divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cPad),
      divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cPad),
      divider.topAnchor.constraint(equalTo: weeklyLabel.bottomAnchor, constant: 6),
      divider.heightAnchor.constraint(equalToConstant: 1),

      // Review row
      reviewLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cPad),
      reviewLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
      reviewLabel.widthAnchor.constraint(equalToConstant: 56),

      reviewPct.leadingAnchor.constraint(equalTo: reviewLabel.trailingAnchor, constant: 4),
      reviewPct.centerYAnchor.constraint(equalTo: reviewLabel.centerYAnchor),
      reviewPct.widthAnchor.constraint(equalToConstant: 40),

      reviewTrack.leadingAnchor.constraint(equalTo: reviewPct.trailingAnchor, constant: 6),
      reviewTrack.centerYAnchor.constraint(equalTo: reviewLabel.centerYAnchor),
      reviewTrack.widthAnchor.constraint(equalToConstant: trackW),
      reviewTrack.heightAnchor.constraint(equalToConstant: LN.progressH),

      reviewDetail.leadingAnchor.constraint(equalTo: reviewTrack.trailingAnchor, constant: 8),
      reviewDetail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cPad),
      reviewDetail.centerYAnchor.constraint(equalTo: reviewLabel.centerYAnchor),

      reviewLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -cPad),
    ])

    wrapper.addSubview(card)
    NSLayoutConstraint.activate([
      wrapper.widthAnchor.constraint(equalToConstant: LN.popoverW),
      card.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: LN.pad),
      card.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -LN.pad),
      card.topAnchor.constraint(equalTo: wrapper.topAnchor),
      card.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
    ])

    return wrapper
  }

  private func configureMetricLabel(_ label: NSTextField) {
    label.font = .systemFont(ofSize: LN.fontSmall, weight: .semibold)
    label.textColor = LN.textTertiary
    label.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureMetricPct(_ label: NSTextField) {
    label.font = .monospacedDigitSystemFont(ofSize: LN.fontSmall, weight: .bold)
    label.textColor = LN.green
    label.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureMetricTrack(_ track: NSView) {
    track.wantsLayer = true
    track.layer?.backgroundColor = LN.elevated.cgColor
    track.layer?.cornerRadius = LN.progressR
    track.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureMetricFill(_ fill: NSView, in track: NSView) {
    fill.wantsLayer = true
    fill.layer?.cornerRadius = LN.progressR
    fill.layer?.backgroundColor = LN.green.cgColor
    fill.translatesAutoresizingMaskIntoConstraints = false
    track.addSubview(fill)
    NSLayoutConstraint.activate([
      fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
      fill.topAnchor.constraint(equalTo: track.topAnchor),
      fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
    ])
  }

  private func configureDetailLabel(_ label: NSTextField) {
    label.font = .systemFont(ofSize: LN.fontMicro, weight: .regular)
    label.textColor = LN.textMuted
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.translatesAutoresizingMaskIntoConstraints = false
  }

  // MARK: - Recommendation Banner

  private func makeRecBanner() -> NSView {
    let wrapper = NSView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false
    recWrapper = wrapper

    recBanner.wantsLayer = true
    recBanner.layer?.cornerRadius = LN.radius
    recBanner.layer?.backgroundColor = LN.yellow.withAlphaComponent(0.08).cgColor
    recBanner.layer?.borderWidth = 1
    recBanner.layer?.borderColor = LN.yellow.withAlphaComponent(0.15).cgColor
    recBanner.translatesAutoresizingMaskIntoConstraints = false

    recIcon.font = .systemFont(ofSize: LN.fontSmall)
    recIcon.textColor = LN.yellow
    recIcon.stringValue = "\u{26A1}"
    recIcon.translatesAutoresizingMaskIntoConstraints = false

    recLabel.font = .systemFont(ofSize: LN.fontSmall, weight: .medium)
    recLabel.textColor = LN.textPrimary
    recLabel.lineBreakMode = .byTruncatingTail
    recLabel.maximumNumberOfLines = 2
    recLabel.translatesAutoresizingMaskIntoConstraints = false

    recBtn.bezelStyle = .texturedRounded
    recBtn.isBordered = false
    recBtn.wantsLayer = true
    recBtn.layer?.cornerRadius = LN.radiusSm
    recBtn.layer?.backgroundColor = LN.yellow.cgColor
    recBtn.font = .systemFont(ofSize: LN.fontMicro, weight: .bold)
    recBtn.contentTintColor = LN.bg
    recBtn.title = " Switch "
    recBtn.target = self
    recBtn.action = #selector(recSwitchTapped)
    recBtn.translatesAutoresizingMaskIntoConstraints = false

    recBanner.addSubview(recIcon)
    recBanner.addSubview(recLabel)
    recBanner.addSubview(recBtn)

    NSLayoutConstraint.activate([
      recIcon.leadingAnchor.constraint(equalTo: recBanner.leadingAnchor, constant: 10),
      recIcon.topAnchor.constraint(equalTo: recBanner.topAnchor, constant: 9),

      recLabel.leadingAnchor.constraint(equalTo: recIcon.trailingAnchor, constant: 4),
      recLabel.topAnchor.constraint(equalTo: recBanner.topAnchor, constant: 8),
      recLabel.bottomAnchor.constraint(lessThanOrEqualTo: recBanner.bottomAnchor, constant: -8),
      recLabel.trailingAnchor.constraint(lessThanOrEqualTo: recBtn.leadingAnchor, constant: -6),

      recBtn.trailingAnchor.constraint(equalTo: recBanner.trailingAnchor, constant: -8),
      recBtn.centerYAnchor.constraint(equalTo: recBanner.centerYAnchor),
      recBtn.heightAnchor.constraint(equalToConstant: 20),
    ])

    wrapper.addSubview(recBanner)
    NSLayoutConstraint.activate([
      wrapper.widthAnchor.constraint(equalToConstant: LN.popoverW),
      wrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
      recBanner.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: LN.pad),
      recBanner.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -LN.pad),
      recBanner.topAnchor.constraint(equalTo: wrapper.topAnchor),
      recBanner.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
    ])

    return wrapper
  }

  // MARK: - Profile Section

  private func makeProfileSection() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    profileHeader.font = .systemFont(ofSize: LN.fontSmall, weight: .semibold)
    profileHeader.textColor = LN.textTertiary
    profileHeader.translatesAutoresizingMaskIntoConstraints = false

    profileStack.orientation = .vertical
    profileStack.spacing = LN.gapXs
    profileStack.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(profileHeader)
    container.addSubview(profileStack)

    NSLayoutConstraint.activate([
      container.widthAnchor.constraint(equalToConstant: LN.popoverW),

      profileHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: LN.pad),
      profileHeader.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LN.pad),
      profileHeader.topAnchor.constraint(equalTo: container.topAnchor),

      profileStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: LN.pad),
      profileStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LN.pad),
      profileStack.topAnchor.constraint(equalTo: profileHeader.bottomAnchor, constant: LN.gapSm),
      profileStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    return container
  }

  // MARK: - Footer

  private func makeFooter() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    footerLabel.font = .systemFont(ofSize: LN.fontMicro, weight: .medium)
    footerLabel.textColor = LN.textMuted
    footerLabel.translatesAutoresizingMaskIntoConstraints = false

    errorLabel.font = .systemFont(ofSize: LN.fontMicro, weight: .medium)
    errorLabel.textColor = LN.yellow
    errorLabel.maximumNumberOfLines = 2
    errorLabel.lineBreakMode = .byWordWrapping
    errorLabel.isHidden = true
    errorLabel.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(footerLabel)
    container.addSubview(errorLabel)

    NSLayoutConstraint.activate([
      container.widthAnchor.constraint(equalToConstant: LN.popoverW),
      container.heightAnchor.constraint(equalToConstant: 32),

      footerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: LN.pad),
      footerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LN.pad),
      footerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),

      errorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: LN.pad),
      errorLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LN.pad),
      errorLabel.topAnchor.constraint(equalTo: footerLabel.bottomAnchor, constant: 1),
    ])

    return container
  }

  // MARK: - Actions

  @objc private func refreshTapped() {
    Task { await monitor.refresh(manual: true) }
  }

  @objc private func recSwitchTapped() {
    guard let pid = recProfileID else { return }
    Task { await monitor.switchToProfile(id: pid) }
  }

  // MARK: - Render

  private func render(state: UsageMonitor.State) {
    updatedLabel.stringValue = state.lastUpdatedLabel
    refreshButton.isEnabled = !state.isRefreshing
    footerLabel.stringValue = state.footerMessage ?? ""
    errorLabel.stringValue = state.errorMessage ?? ""
    errorLabel.isHidden = state.errorMessage == nil

    let activeProfile = state.profiles.first(where: { $0.id == state.activeProfileID })

    guard let snapshot = state.snapshot else {
      renderLoading(activeProfile: activeProfile)
      renderProfiles(state: state)
      return
    }

    renderPrimary(snapshot: snapshot, state: state, activeProfile: activeProfile)
    renderQuotas(snapshot: snapshot, state: state)
    renderRec(state: state)
    renderProfiles(state: state)
  }

  private func renderLoading(activeProfile: AuthProfileRecord?) {
    accountLabel.stringValue = activeProfile?.displayName ?? "Loading..."
    statusDot.layer?.backgroundColor = LN.textMuted.cgColor
    statusBadgeLbl.stringValue = "Syncing"
    statusBadge.layer?.backgroundColor = LN.textMuted.withAlphaComponent(0.12).cgColor
    statusBadgeLbl.textColor = LN.textMuted
    heroNumber.stringValue = "--"
    heroNumber.textColor = LN.textMuted
    heroSuffix.textColor = LN.textMuted.withAlphaComponent(0.5)
    heroSubline.stringValue = "Waiting for first sync"
    primaryFillW?.constant = 0
    recWrapper?.isHidden = true
  }

  private func renderPrimary(snapshot: UsageSnapshot, state: UsageMonitor.State,
                             activeProfile: AuthProfileRecord?) {
    accountLabel.stringValue = activeProfile?.displayName ?? "Current"

    // Update section label with plan type
    let planName = snapshot.planType.lowercased() == "team" ? "Team" : "Plus"
    primarySectionLabel.stringValue = "\(planName) · 5h Primary Quota"

    let rl = snapshot.rateLimit
    let authAccent = Self.authAccent(for: rl)
    statusDot.layer?.backgroundColor = authAccent.cgColor
    statusBadgeLbl.stringValue = state.availabilityLabel(for: rl)
    statusBadge.layer?.backgroundColor = authAccent.withAlphaComponent(0.12).cgColor
    statusBadgeLbl.textColor = authAccent

    // Use effective available percent (considering both primary and weekly)
    let effectivePct: Double
    if let secondaryUsedPercent = snapshot.rateLimit.secondaryWindow?.usedPercent, secondaryUsedPercent >= 100 {
        effectivePct = 0
    } else {
        effectivePct = rl.primaryWindow.remainingPercent
    }
    let accent = Self.accentColor(for: effectivePct)
    let pctInt = Int(effectivePct.rounded())
    heroNumber.stringValue = String(pctInt)
    heroNumber.textColor = accent
    heroSuffix.textColor = accent.withAlphaComponent(0.5)
    heroSubline.stringValue = state.primaryBurnLabel(for: rl)

    let innerW = LN.popoverW - LN.pad * 2 - LN.cardPad * 2
    primaryFillW?.constant = innerW * CGFloat(effectivePct / 100)
    primaryFill.layer?.backgroundColor = accent.cgColor
  }

  private func renderQuotas(snapshot: UsageSnapshot, state: UsageMonitor.State) {
    let trackW: CGFloat = 100

    if let w = snapshot.rateLimit.secondaryWindow {
      weeklyLabel.isHidden = false
      weeklyPct.isHidden = false
      weeklyTrack.isHidden = false
      weeklyDetail.isHidden = false
      let pct = w.remainingPercent
      let accent = Self.accentColor(for: pct)
      let pctInt = Int(pct.rounded())
      weeklyPct.stringValue = String(pctInt) + "%"
      weeklyPct.textColor = accent
      weeklyFillW?.constant = trackW * CGFloat(pct / 100)
      weeklyFill.layer?.backgroundColor = accent.cgColor
      weeklyDetail.stringValue = state.weeklyBurnLabel(for: snapshot.rateLimit)
    } else {
      weeklyLabel.isHidden = true
      weeklyPct.isHidden = true
      weeklyTrack.isHidden = true
      weeklyDetail.isHidden = true
    }

    let rw = snapshot.codeReviewRateLimit.primaryWindow
    let rPct = rw.remainingPercent
    let rAccent = Self.accentColor(for: rPct)
    let rPctInt = Int(rPct.rounded())
    reviewPct.stringValue = String(rPctInt) + "%"
    reviewPct.textColor = rAccent
    reviewFillW?.constant = trackW * CGFloat(rPct / 100)
    reviewFill.layer?.backgroundColor = rAccent.cgColor
    reviewDetail.stringValue = state.burnLabel(from: state.reviewEstimate)
  }

  private func renderRec(state: UsageMonitor.State) {
    let rec = state.switchRecommendation
    if rec.kind == .switchNow, let pid = rec.recommendedProfileID {
      recWrapper?.isHidden = false
      recProfileID = pid
      recLabel.stringValue = rec.headline
      recBanner.layer?.backgroundColor = LN.yellow.withAlphaComponent(0.08).cgColor
      recBanner.layer?.borderColor = LN.yellow.withAlphaComponent(0.15).cgColor
      recIcon.stringValue = "\u{26A1}"
      recIcon.textColor = LN.yellow
      recBtn.layer?.backgroundColor = LN.yellow.cgColor
      recBtn.title = " Switch "
      recBtn.isHidden = false
    } else if rec.kind == .noAvailable {
      recWrapper?.isHidden = false
      recProfileID = nil
      recLabel.stringValue = rec.headline + " \u{00B7} " + rec.detail
      recBanner.layer?.backgroundColor = LN.red.withAlphaComponent(0.06).cgColor
      recBanner.layer?.borderColor = LN.red.withAlphaComponent(0.12).cgColor
      recIcon.stringValue = "\u{26A0}"
      recIcon.textColor = LN.red
      recBtn.isHidden = true
    } else {
      recWrapper?.isHidden = true
    }
  }

  private func renderProfiles(state: UsageMonitor.State) {
    profileStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let others = state.profiles.filter { $0.id != state.activeProfileID && $0.validationError?.contains("402") != true }
    let availCount = others.filter { $0.validationError == nil && $0.latestUsage?.isBlocked != true }.count
    profileHeader.stringValue = "Other Profiles  \u{00B7}  \(availCount) available"

    if others.isEmpty {
      profileHeader.stringValue = "No other profiles"
      return
    }

    for profile in others {
      let row = ProfileRowView()
      row.configure(
        profile: profile,
        isRecommended: profile.id == state.switchRecommendation.recommendedProfileID,
        isBusy: state.isRefreshing
      ) { [weak self] in
        self?.confirmSwitch(to: profile)
      }
      profileStack.addArrangedSubview(row)
    }
  }

  private func confirmSwitch(to profile: AuthProfileRecord) {
    let alert = NSAlert()
    alert.messageText = "Switch to this account?"
    alert.informativeText = "Will overwrite ~/.codex/auth.json with \(profile.displayName). A backup will be created."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Switch")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
      Task { await monitor.switchToProfile(id: profile.id) }
    }
  }

  // MARK: - Helpers

  static func accentColor(for pct: Double) -> NSColor {
    switch pct {
    case 60...100: return LN.green
    case 26..<60:  return LN.yellow
    default:       return LN.red
    }
  }

  private static func authAccent(for rl: UsageLimit) -> NSColor {
    if let w = rl.secondaryWindow, w.remainingPercent <= 0 { return LN.red }
    if !rl.allowed || rl.limitReached || rl.primaryWindow.remainingPercent <= 0 { return LN.red }
    return accentColor(for: rl.primaryWindow.remainingPercent)
  }

  static func planName(for v: String) -> String {
    switch v.lowercased() {
    case "team": return "Team"
    case "plus": return "Plus"
    default: return v.capitalized
    }
  }
}

// MARK: - ProfileRowView

private final class ProfileRowView: NSView {
  private let dot         = NSView()
  private let nameLabel   = NSTextField(labelWithString: "")
  private let usageLabel  = NSTextField(labelWithString: "")
  private let switchBtn   = NSButton()
  private var onSwitch: (() -> Void)?

  override init(frame: NSRect) { super.init(frame: frame); setup() }
  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  private func setup() {
    wantsLayer = true
    layer?.cornerRadius = LN.radiusSm
    layer?.backgroundColor = LN.surfaceHover.cgColor
    translatesAutoresizingMaskIntoConstraints = false

    dot.wantsLayer = true
    dot.layer?.cornerRadius = 3
    dot.translatesAutoresizingMaskIntoConstraints = false

    nameLabel.font = .systemFont(ofSize: LN.fontSmall, weight: .medium)
    nameLabel.textColor = LN.textPrimary
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.maximumNumberOfLines = 1
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    usageLabel.font = .systemFont(ofSize: LN.fontMicro, weight: .regular)
    usageLabel.textColor = LN.textTertiary
    usageLabel.lineBreakMode = .byTruncatingTail
    usageLabel.maximumNumberOfLines = 1
    usageLabel.translatesAutoresizingMaskIntoConstraints = false
    usageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    switchBtn.bezelStyle = .texturedRounded
    switchBtn.isBordered = false
    switchBtn.wantsLayer = true
    switchBtn.layer?.cornerRadius = LN.radiusSm
    switchBtn.layer?.backgroundColor = LN.elevated.cgColor
    switchBtn.font = .systemFont(ofSize: LN.fontMicro, weight: .semibold)
    switchBtn.contentTintColor = LN.textSecondary
    switchBtn.target = self
    switchBtn.action = #selector(tapped)
    switchBtn.translatesAutoresizingMaskIntoConstraints = false
    switchBtn.setContentCompressionResistancePriority(.required, for: .horizontal)

    addSubview(dot)
    addSubview(nameLabel)
    addSubview(usageLabel)
    addSubview(switchBtn)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 36),

      dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      dot.centerYAnchor.constraint(equalTo: centerYAnchor),
      dot.widthAnchor.constraint(equalToConstant: 6),
      dot.heightAnchor.constraint(equalToConstant: 6),

      nameLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
      nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      nameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 120),

      usageLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
      usageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      usageLabel.trailingAnchor.constraint(lessThanOrEqualTo: switchBtn.leadingAnchor, constant: -6),

      switchBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      switchBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
      switchBtn.heightAnchor.constraint(equalToConstant: 20),
    ])
  }

  func configure(profile: AuthProfileRecord, isRecommended: Bool,
                 isBusy: Bool, onSwitch: @escaping () -> Void) {
    self.onSwitch = onSwitch
    nameLabel.stringValue = profile.displayName

    let accent: NSColor
    if profile.validationError != nil || profile.latestUsage?.isBlocked == true {
      accent = LN.red
      usageLabel.stringValue = profile.statusText
      layer?.backgroundColor = LN.red.withAlphaComponent(0.06).cgColor
    } else if let usage = profile.latestUsage {
      let pct = usage.effectiveRemainingPercent
      accent = PopoverViewController.accentColor(for: pct)
      usageLabel.stringValue = usage.switchSummaryText
      layer?.backgroundColor = LN.surfaceHover.cgColor
    } else {
      accent = LN.textMuted
      usageLabel.stringValue = "Validating..."
      layer?.backgroundColor = LN.surfaceHover.cgColor
    }

    dot.layer?.backgroundColor = accent.cgColor

    if isRecommended {
      switchBtn.title = " Recommend "
      switchBtn.layer?.backgroundColor = LN.yellow.withAlphaComponent(0.12).cgColor
      switchBtn.contentTintColor = LN.yellow
    } else {
      switchBtn.title = " Use "
      switchBtn.layer?.backgroundColor = LN.elevated.cgColor
      switchBtn.contentTintColor = LN.textSecondary
    }
    switchBtn.isEnabled = !isBusy && profile.validationError == nil
  }

  @objc private func tapped() { onSwitch?() }
}
