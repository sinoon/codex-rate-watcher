import AppKit
import CodexRateKit

private enum Desk {
  static let background = NSColor(srgbRed: 0.031, green: 0.047, blue: 0.071, alpha: 1)
  static let card = NSColor(srgbRed: 0.071, green: 0.098, blue: 0.137, alpha: 1)
  static let cardAlt = NSColor(srgbRed: 0.082, green: 0.114, blue: 0.157, alpha: 1)
  static let cardHero = NSColor(srgbRed: 0.086, green: 0.129, blue: 0.184, alpha: 1)
  static let border = NSColor(srgbRed: 0.165, green: 0.220, blue: 0.286, alpha: 1)
  static let borderStrong = NSColor(srgbRed: 0.239, green: 0.325, blue: 0.420, alpha: 1)
  static let textPrimary = NSColor(srgbRed: 0.925, green: 0.945, blue: 0.973, alpha: 1)
  static let textSecondary = NSColor(srgbRed: 0.631, green: 0.706, blue: 0.780, alpha: 1)
  static let textMuted = NSColor(srgbRed: 0.463, green: 0.533, blue: 0.608, alpha: 1)
  static let accent = NSColor(srgbRed: 0.482, green: 0.761, blue: 0.957, alpha: 1)
  static let accentSoft = NSColor(srgbRed: 0.482, green: 0.761, blue: 0.957, alpha: 0.14)
  static let green = NSColor(srgbRed: 0.373, green: 0.831, blue: 0.596, alpha: 1)
  static let yellow = NSColor(srgbRed: 0.957, green: 0.792, blue: 0.384, alpha: 1)
  static let red = NSColor(srgbRed: 0.941, green: 0.424, blue: 0.424, alpha: 1)

  static let radius: CGFloat = 20
  static let cardPadding: CGFloat = 18
  static let gap: CGFloat = 16
  static let contentWidth: CGFloat = 1200
  static let mainColumnWidth: CGFloat = 788
  static let railWidth: CGFloat = 396
}

@MainActor
final class TokenCostDashboardViewController: NSViewController {
  private enum RangeSelection: Int, CaseIterable {
    case seven = 0
    case thirty = 1
    case ninety = 2

    var days: Int {
      switch self {
      case .seven: return 7
      case .thirty: return 30
      case .ninety: return 90
      }
    }

    var title: String {
      "\(days)D"
    }
  }

  private let monitor: UsageMonitor
  private var observerID: UUID?
  private var latestSnapshot: TokenCostSnapshot?
  private var selectedRange: RangeSelection = .thirty

  private let scrollView = NSScrollView()
  private let contentView = DeskFlippedView()
  private let contentStack = NSStackView()
  private let emptyStateCard = DeskCardView(title: Copy.dashboardEmptyTitle)
  private let analyticsStack = NSStackView()
  private let bodyRowStack = NSStackView()
  private let mainColumnStack = NSStackView()
  private let sideRailStack = NSStackView()

  private let titleLabel = NSTextField(labelWithString: Copy.dashboardTitle)
  private let subtitleLabel = NSTextField(labelWithString: Copy.dashboardSubtitle)
  private let updatedLabel = NSTextField(labelWithString: "")
  private let headerEyebrowLabel = NSTextField(labelWithString: Copy.dashboardEyebrowLocal)
  private let headerSummaryLabel = NSTextField(labelWithString: "")
  private let partialBadge = NSTextField(labelWithString: Copy.dashboardPartialPricing)
  private let rangeControl = NSSegmentedControl(labels: RangeSelection.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
  private let refreshButton = NSButton()
  private let exportButton = NSButton()

  private let todayCostCard = DeskMetricCardView()
  private let windowCostCard = DeskMetricCardView()
  private let todayTokensCard = DeskMetricCardView()
  private let dominantModelCard = DeskMetricCardView()
  private let digestCard = DeskCardView(title: "Window Digest")
  private let digestValueLabel = NSTextField(labelWithString: "")
  private let digestDetailLabel = NSTextField(labelWithString: "")
  private let digestMetricsStack = NSStackView()

  private let timelineCard = DeskCardView(title: Copy.dashboardBurnTimeline)
  private let timelineSummaryLabel = NSTextField(labelWithString: "")
  private let timelineChartView = DeskTimelineChartView()

  private let alertCard = DeskCardView(title: Copy.dashboardAlertRail)
  private let alertStack = NSStackView()

  private let accountCard = DeskCardView(title: Copy.dashboardAccountLeaderboard)
  private let accountStack = NSStackView()

  private let modelCard = DeskCardView(title: Copy.dashboardModelLeaderboard)
  private let modelStack = NSStackView()

  private let structureCard = DeskCardView(title: Copy.dashboardCostStructure)
  private let structureStack = NSStackView()

  private let hourlyCard = DeskCardView(title: Copy.dashboardHourlyHeatmap)
  private let hourlyCaptionLabel = NSTextField(labelWithString: "")
  private let heatmapView = DeskHeatmapView()

  private let dailyTableCard = DeskCardView(title: Copy.dashboardDailyDetail)
  private let tableHeaderRow = NSStackView()
  private let tableRowsStack = NSStackView()

  private let narrativeCard = DeskCardView(title: Copy.dashboardNarrative)
  private let whatChangedStack = NSStackView()
  private let whatHelpedStack = NSStackView()
  private let whatToWatchStack = NSStackView()

  init(monitor: UsageMonitor) {
    self.monitor = monitor
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override func loadView() {
    let view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = Desk.background.cgColor
    self.view = view
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    buildLayout()
    observerID = monitor.addObserver { [weak self] state in
      DispatchQueue.main.async {
        self?.render(state: state)
      }
    }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    updateDocumentLayout()
  }

  deinit {
    if let observerID {
      let monitor = monitor
      Task { @MainActor in
        monitor.removeObserver(observerID)
      }
    }
  }

  internal func renderForTesting(snapshot: TokenCostSnapshot?) {
    latestSnapshot = snapshot
    renderContent()
  }

  private func buildLayout() {
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)

    contentView.frame = NSRect(x: 0, y: 0, width: Desk.contentWidth + 40, height: 100)
    scrollView.documentView = contentView

    contentStack.orientation = .vertical
    contentStack.spacing = Desk.gap
    contentStack.alignment = .leading
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(contentStack)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      contentStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
      contentStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
      contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
      contentStack.widthAnchor.constraint(equalToConstant: Desk.contentWidth),
    ])

    analyticsStack.orientation = .vertical
    analyticsStack.spacing = Desk.gap
    analyticsStack.alignment = .leading
    analyticsStack.translatesAutoresizingMaskIntoConstraints = false

    bodyRowStack.orientation = .horizontal
    bodyRowStack.alignment = .top
    bodyRowStack.spacing = Desk.gap
    bodyRowStack.translatesAutoresizingMaskIntoConstraints = false
    bodyRowStack.widthAnchor.constraint(equalToConstant: Desk.contentWidth).isActive = true

    mainColumnStack.orientation = .vertical
    mainColumnStack.alignment = .leading
    mainColumnStack.spacing = Desk.gap
    mainColumnStack.translatesAutoresizingMaskIntoConstraints = false
    mainColumnStack.widthAnchor.constraint(equalToConstant: Desk.mainColumnWidth).isActive = true

    sideRailStack.orientation = .vertical
    sideRailStack.alignment = .leading
    sideRailStack.spacing = Desk.gap
    sideRailStack.translatesAutoresizingMaskIntoConstraints = false
    sideRailStack.widthAnchor.constraint(equalToConstant: Desk.railWidth).isActive = true

    configureDigestCard()
    configureTimelineCard()
    configureAlertCard()
    configureAccountCard()
    configureModelCard()
    configureStructureCard()
    configureHourlyCard()
    configureDailyTableCard()
    configureNarrativeCard()

    mainColumnStack.addArrangedSubview(makeOverviewGrid())
    mainColumnStack.addArrangedSubview(timelineCard)
    mainColumnStack.addArrangedSubview(dailyTableCard)

    sideRailStack.addArrangedSubview(digestCard)
    sideRailStack.addArrangedSubview(alertCard)
    sideRailStack.addArrangedSubview(accountCard)
    sideRailStack.addArrangedSubview(modelCard)
    sideRailStack.addArrangedSubview(hourlyCard)
    sideRailStack.addArrangedSubview(structureCard)
    sideRailStack.addArrangedSubview(narrativeCard)

    bodyRowStack.addArrangedSubview(mainColumnStack)
    bodyRowStack.addArrangedSubview(sideRailStack)

    analyticsStack.addArrangedSubview(bodyRowStack)

    configureEmptyState()

    contentStack.addArrangedSubview(makeHeader())
    contentStack.addArrangedSubview(emptyStateCard)
    contentStack.addArrangedSubview(analyticsStack)

    renderContent()
  }

  private func updateDocumentLayout() {
    guard scrollView.bounds.width > 0 else { return }

    let viewportWidth = max(scrollView.contentSize.width, Desk.contentWidth + 40)
    if contentView.frame.width != viewportWidth {
      contentView.frame.size.width = viewportWidth
    }

    contentView.layoutSubtreeIfNeeded()
    let fittingHeight = contentStack.fittingSize.height + 40
    let viewportHeight = scrollView.contentSize.height
    let targetHeight = max(fittingHeight, viewportHeight)
    if contentView.frame.height != targetHeight {
      contentView.frame.size.height = targetHeight
    }
  }

  private func configureEmptyState() {
    emptyStateCard.subtitleLabel.stringValue = Copy.dashboardEmptyBody
    let detail = NSTextField(labelWithString: "The dashboard updates lazily from local session logs and keeps its cache warm for fast refreshes.")
    detail.font = .systemFont(ofSize: 13, weight: .medium)
    detail.textColor = Desk.textMuted
    detail.lineBreakMode = .byWordWrapping
    detail.maximumNumberOfLines = 0
    emptyStateCard.contentStack.addArrangedSubview(detail)
  }

  private func makeHeader() -> NSView {
    let wrapper = DeskCardView(title: Copy.dashboardTitle)
    wrapper.translatesAutoresizingMaskIntoConstraints = false
    wrapper.widthAnchor.constraint(equalToConstant: Desk.contentWidth).isActive = true
    wrapper.layer?.backgroundColor = Desk.cardHero.cgColor
    wrapper.layer?.borderColor = Desk.borderStrong.cgColor
    wrapper.titleLabel.isHidden = true
    wrapper.subtitleLabel.isHidden = true

    headerEyebrowLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
    headerEyebrowLabel.textColor = Desk.accent
    headerEyebrowLabel.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
    titleLabel.textColor = Desk.textPrimary
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    subtitleLabel.textColor = Desk.textSecondary
    subtitleLabel.lineBreakMode = .byWordWrapping
    subtitleLabel.maximumNumberOfLines = 0
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

    updatedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    updatedLabel.textColor = Desk.textMuted
    updatedLabel.translatesAutoresizingMaskIntoConstraints = false

    headerSummaryLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    headerSummaryLabel.textColor = Desk.textSecondary
    headerSummaryLabel.lineBreakMode = .byWordWrapping
    headerSummaryLabel.maximumNumberOfLines = 0
    headerSummaryLabel.translatesAutoresizingMaskIntoConstraints = false

    partialBadge.font = .systemFont(ofSize: 11, weight: .bold)
    partialBadge.textColor = Desk.yellow
    partialBadge.alignment = .center
    partialBadge.wantsLayer = true
    partialBadge.layer?.backgroundColor = Desk.yellow.withAlphaComponent(0.12).cgColor
    partialBadge.layer?.cornerRadius = 8
    partialBadge.translatesAutoresizingMaskIntoConstraints = false
    partialBadge.isHidden = true
    partialBadge.setContentHuggingPriority(.required, for: .horizontal)

    rangeControl.selectedSegment = RangeSelection.thirty.rawValue
    rangeControl.segmentStyle = .rounded
    rangeControl.target = self
    rangeControl.action = #selector(rangeChanged)
    rangeControl.translatesAutoresizingMaskIntoConstraints = false

    configureHeaderButton(refreshButton, title: Copy.dashboardRefresh, action: #selector(refreshTapped))
    configureHeaderButton(exportButton, title: Copy.dashboardCopyJSON, action: #selector(copyJSONTapped))

    let titleStack = NSStackView(views: [headerEyebrowLabel, titleLabel, subtitleLabel, headerSummaryLabel, updatedLabel])
    titleStack.orientation = .vertical
    titleStack.spacing = 6
    titleStack.translatesAutoresizingMaskIntoConstraints = false

    let controlsStack = NSStackView(views: [partialBadge, rangeControl, refreshButton, exportButton])
    controlsStack.orientation = .horizontal
    controlsStack.alignment = .centerY
    controlsStack.spacing = 10
    controlsStack.translatesAutoresizingMaskIntoConstraints = false

    wrapper.contentStack.orientation = .horizontal
    wrapper.contentStack.alignment = .top
    wrapper.contentStack.spacing = 24
    wrapper.contentStack.addArrangedSubview(titleStack)
    wrapper.contentStack.addArrangedSubview(controlsStack)
    titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
    controlsStack.setContentHuggingPriority(.required, for: .horizontal)

    return wrapper
  }

  private func configureHeaderButton(_ button: NSButton, title: String, action: Selector) {
    button.title = title
    button.isBordered = false
    button.bezelStyle = .texturedRounded
    button.font = .systemFont(ofSize: 11, weight: .semibold)
    button.contentTintColor = Desk.textPrimary
    button.wantsLayer = true
    button.layer?.backgroundColor = Desk.cardAlt.cgColor
    button.layer?.cornerRadius = 9
    button.target = self
    button.action = action
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 82).isActive = true
    button.heightAnchor.constraint(equalToConstant: 30).isActive = true
  }

  private func makeOverviewGrid() -> NSView {
    let topRow = NSStackView(views: [todayCostCard, windowCostCard])
    topRow.orientation = .horizontal
    topRow.distribution = .fillEqually
    topRow.spacing = Desk.gap

    let bottomRow = NSStackView(views: [todayTokensCard, dominantModelCard])
    bottomRow.orientation = .horizontal
    bottomRow.distribution = .fillEqually
    bottomRow.spacing = Desk.gap

    let stack = NSStackView(views: [topRow, bottomRow])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = Desk.gap
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.widthAnchor.constraint(equalToConstant: Desk.mainColumnWidth).isActive = true

    todayCostCard.configure(title: Copy.dashboardTodayCost, value: Copy.dashboardNoDataPlaceholder, detail: "")
    windowCostCard.configure(title: Copy.dashboardRangeCost, value: Copy.dashboardNoDataPlaceholder, detail: "")
    todayTokensCard.configure(title: Copy.dashboardTodayTokens, value: Copy.dashboardNoDataPlaceholder, detail: "")
    dominantModelCard.configure(title: Copy.dashboardDominantModel, value: Copy.dashboardNoDataPlaceholder, detail: "")

    return stack
  }

  private func configureTimelineCard() {
    timelineCard.titleLabel.textColor = Desk.textPrimary
    timelineCard.titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
    timelineCard.layer?.borderColor = Desk.borderStrong.cgColor

    timelineSummaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
    timelineSummaryLabel.textColor = Desk.textSecondary
    timelineSummaryLabel.translatesAutoresizingMaskIntoConstraints = false

    timelineChartView.translatesAutoresizingMaskIntoConstraints = false
    timelineChartView.heightAnchor.constraint(equalToConstant: 260).isActive = true

    timelineCard.contentStack.spacing = 10
    timelineCard.contentStack.addArrangedSubview(timelineSummaryLabel)
    timelineCard.contentStack.addArrangedSubview(timelineChartView)
    timelineCard.widthAnchor.constraint(equalToConstant: Desk.mainColumnWidth).isActive = true
  }

  private func configureAlertCard() {
    alertStack.orientation = .vertical
    alertStack.spacing = 10
    alertStack.translatesAutoresizingMaskIntoConstraints = false
    alertCard.contentStack.addArrangedSubview(alertStack)
    alertCard.widthAnchor.constraint(equalToConstant: Desk.railWidth).isActive = true
  }

  private func configureAccountCard() {
    accountStack.orientation = .vertical
    accountStack.spacing = 10
    accountStack.translatesAutoresizingMaskIntoConstraints = false
    accountCard.contentStack.addArrangedSubview(accountStack)
    accountCard.widthAnchor.constraint(equalToConstant: Desk.railWidth).isActive = true
  }

  private func configureModelCard() {
    modelStack.orientation = .vertical
    modelStack.spacing = 10
    modelStack.translatesAutoresizingMaskIntoConstraints = false
    modelCard.contentStack.addArrangedSubview(modelStack)
    modelCard.widthAnchor.constraint(equalToConstant: Desk.railWidth).isActive = true
  }

  private func configureStructureCard() {
    structureStack.orientation = .vertical
    structureStack.spacing = 10
    structureStack.translatesAutoresizingMaskIntoConstraints = false
    structureCard.contentStack.addArrangedSubview(structureStack)
    structureCard.widthAnchor.constraint(equalToConstant: Desk.railWidth).isActive = true
  }

  private func configureHourlyCard() {
    hourlyCaptionLabel.font = .systemFont(ofSize: 12, weight: .medium)
    hourlyCaptionLabel.textColor = Desk.textSecondary
    hourlyCaptionLabel.translatesAutoresizingMaskIntoConstraints = false
    heatmapView.translatesAutoresizingMaskIntoConstraints = false
    heatmapView.heightAnchor.constraint(equalToConstant: 208).isActive = true
    hourlyCard.contentStack.spacing = 10
    hourlyCard.contentStack.addArrangedSubview(hourlyCaptionLabel)
    hourlyCard.contentStack.addArrangedSubview(heatmapView)
    hourlyCard.widthAnchor.constraint(equalToConstant: Desk.railWidth).isActive = true
  }

  private func configureDailyTableCard() {
    dailyTableCard.titleLabel.textColor = Desk.textPrimary
    dailyTableCard.titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
    dailyTableCard.layer?.borderColor = Desk.borderStrong.cgColor

    configureTableHeader()

    dailyTableCard.contentStack.spacing = 10
    dailyTableCard.contentStack.addArrangedSubview(tableHeaderRow)
    dailyTableCard.contentStack.addArrangedSubview(tableRowsStack)
    dailyTableCard.widthAnchor.constraint(equalToConstant: Desk.mainColumnWidth).isActive = true
  }

  private func configureNarrativeCard() {
    narrativeCard.contentStack.spacing = 14
    narrativeCard.contentStack.addArrangedSubview(makeNarrativeSection(title: Copy.dashboardWhatChanged, stack: whatChangedStack))
    narrativeCard.contentStack.addArrangedSubview(makeNarrativeSection(title: Copy.dashboardWhatHelped, stack: whatHelpedStack))
    narrativeCard.contentStack.addArrangedSubview(makeNarrativeSection(title: Copy.dashboardWhatToWatch, stack: whatToWatchStack))
    narrativeCard.widthAnchor.constraint(equalToConstant: Desk.railWidth).isActive = true
  }

  private func configureDigestCard() {
    digestValueLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
    digestValueLabel.textColor = Desk.textPrimary
    digestValueLabel.translatesAutoresizingMaskIntoConstraints = false

    digestDetailLabel.font = .systemFont(ofSize: 12, weight: .medium)
    digestDetailLabel.textColor = Desk.textSecondary
    digestDetailLabel.lineBreakMode = .byWordWrapping
    digestDetailLabel.maximumNumberOfLines = 0
    digestDetailLabel.translatesAutoresizingMaskIntoConstraints = false

    digestMetricsStack.orientation = .vertical
    digestMetricsStack.spacing = 8
    digestMetricsStack.translatesAutoresizingMaskIntoConstraints = false

    digestCard.contentStack.spacing = 12
    digestCard.contentStack.addArrangedSubview(digestValueLabel)
    digestCard.contentStack.addArrangedSubview(digestDetailLabel)
    digestCard.contentStack.addArrangedSubview(digestMetricsStack)
    digestCard.widthAnchor.constraint(equalToConstant: Desk.railWidth).isActive = true
  }

  private func configureTableHeader() {
    tableHeaderRow.orientation = .horizontal
    tableHeaderRow.distribution = .fill
    tableHeaderRow.spacing = 8
    tableHeaderRow.translatesAutoresizingMaskIntoConstraints = false
    if !tableHeaderRow.arrangedSubviews.isEmpty {
      return
    }

    let titles = ["Date", "Cost", "Input", "Cache", "Output", "Dominant"]
    let widths: [CGFloat] = [112, 92, 106, 106, 106, 186]
    for (index, title) in titles.enumerated() {
      let label = makeLedgerLabel(title, bold: true, alignRight: index == 5)
      label.widthAnchor.constraint(equalToConstant: widths[index]).isActive = true
      tableHeaderRow.addArrangedSubview(label)
    }

    tableRowsStack.orientation = .vertical
    tableRowsStack.spacing = 6
    tableRowsStack.translatesAutoresizingMaskIntoConstraints = false
  }

  private func makeNarrativeSection(title: String, stack: NSStackView) -> NSView {
    stack.orientation = .vertical
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
    titleLabel.textColor = Desk.textPrimary
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let container = NSStackView(views: [titleLabel, stack])
    container.orientation = .vertical
    container.spacing = 8
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
  }

  private func render(state: UsageMonitor.State) {
    latestSnapshot = state.tokenCostSnapshot
    renderContent()
  }

  private func renderContent() {
    guard let snapshot = latestSnapshot, snapshot.hasAnyData else {
      updatedLabel.stringValue = ""
      partialBadge.isHidden = true
      analyticsStack.isHidden = true
      emptyStateCard.isHidden = false
      return
    }

    emptyStateCard.isHidden = true
    analyticsStack.isHidden = false

    let rangeDays = selectedRange.days
    let window = snapshot.windowSummary(days: rangeDays)
    let isMerged = snapshot.source?.mode == .iCloudMerged

    headerEyebrowLabel.stringValue = isMerged ? Copy.dashboardEyebrowAllDevices : Copy.dashboardEyebrowLocal
    subtitleLabel.stringValue = isMerged ? Copy.dashboardSubtitleAllDevices : Copy.dashboardSubtitle

    updatedLabel.stringValue = "\(Copy.dashboardUpdatedPrefix) \(timestampString(snapshot.updatedAt))"
    partialBadge.isHidden = !(window?.hasPartialPricing ?? false)
    headerSummaryLabel.stringValue = headerSummary(window: window)

    todayCostCard.configure(
      title: Copy.dashboardTodayCost,
      value: usd(snapshot.todayCostUSD),
      detail: isMerged ? "All-device burn" : "Latest local burn"
    )

    windowCostCard.configure(
      title: "\(rangeDays)D Cost",
      value: usd(window?.totalCostUSD),
      detail: averageDaily(window?.averageDailyCostUSD)
    )

    todayTokensCard.configure(
      title: Copy.dashboardTodayTokens,
      value: tokenCount(snapshot.todayTokens),
      detail: isMerged ? "All-device total" : "Local log total"
    )

    let dominantShare = window?.modelSummaries.first?.costShare ?? window?.modelSummaries.first?.tokenShare
    dominantModelCard.configure(
      title: Copy.dashboardDominantModel,
      value: window?.dominantModelName ?? Copy.dashboardNoDataPlaceholder,
      detail: percent(dominantShare)
    )

    renderDigest(window)

    timelineSummaryLabel.stringValue = timelineSummary(window: window)
    timelineChartView.points = buildTimelinePoints(snapshot: snapshot, rangeDays: rangeDays)

    renderAlerts(window)
    renderAccountLeaderboard(snapshot.accountSummaries)
    renderModelLeaderboard(window)
    renderCostStructure(window)
    hourlyCaptionLabel.stringValue = "\(rangeDays)D \(isMerged ? "all-device" : "local-hour") aggregation"
    heatmapView.entries = window?.hourly ?? []
    renderDailyTable(snapshot: snapshot, rangeDays: rangeDays)
    renderNarrative(window?.narrative ?? .init())
    updateDocumentLayout()
  }

  private func renderDigest(_ window: TokenCostWindowSummary?) {
    digestValueLabel.stringValue = usd(window?.totalCostUSD)
    digestDetailLabel.stringValue = "\(selectedRange.days)D visible spend · \(tokenCount(window?.totalTokens)) · \(window?.activeDayCount ?? 0) active days"

    clearArrangedSubviews(digestMetricsStack)
    let rows: [(String, String)] = [
      ("Average / day", averageDaily(window?.averageDailyCostUSD)),
      (Copy.dashboardCacheShare, percent(window?.cacheShare)),
      ("Active days", "\(window?.activeDayCount ?? 0)"),
      ("Pricing status", (window?.hasPartialPricing ?? false) ? "Partial" : "Complete"),
    ]

    for row in rows {
      digestMetricsStack.addArrangedSubview(DeskMiniMetricRowView(title: row.0, value: row.1))
    }
  }

  private func renderAlerts(_ window: TokenCostWindowSummary?) {
    clearArrangedSubviews(alertStack)

    let alerts = window?.alerts ?? []
    if alerts.isEmpty {
      alertStack.addArrangedSubview(makePlaceholderLabel(Copy.dashboardNoAlerts))
      return
    }

    for alert in alerts {
      alertStack.addArrangedSubview(DeskAlertView(alert: alert))
    }
  }

  private func renderAccountLeaderboard(_ summaries: [TokenCostAccountSummary]) {
    clearArrangedSubviews(accountStack)

    if summaries.isEmpty {
      accountStack.addArrangedSubview(makePlaceholderLabel(Copy.dashboardNoRows))
      return
    }

    let maxTokens = max(summaries.compactMap(\.last30DaysTokens).max() ?? 1, 1)
    for summary in summaries.prefix(6) {
      let fraction = Double(summary.last30DaysTokens ?? 0) / Double(maxTokens)
      accountStack.addArrangedSubview(
        DeskLeaderboardRowView(
          title: summary.displayName,
          subtitle: "\(usd(summary.last30DaysCostUSD)) · \(TokenCostFormatting.tokenCount(summary.last30DaysTokens ?? 0))",
          fraction: fraction
        )
      )
    }
  }

  private func renderModelLeaderboard(_ window: TokenCostWindowSummary?) {
    clearArrangedSubviews(modelStack)

    let summaries = window?.modelSummaries ?? []
    if summaries.isEmpty {
      modelStack.addArrangedSubview(makePlaceholderLabel(Copy.dashboardNoRows))
      return
    }

    for summary in summaries.prefix(6) {
      let share = summary.costShare ?? summary.tokenShare ?? 0
      modelStack.addArrangedSubview(
        DeskLeaderboardRowView(
          title: summary.modelName,
          subtitle: "\(usd(summary.costUSD)) · \(TokenCostFormatting.tokenCount(summary.totalTokens))",
          fraction: share
        )
      )
    }
  }

  private func renderCostStructure(_ window: TokenCostWindowSummary?) {
    clearArrangedSubviews(structureStack)

    let summaries = window?.modelSummaries ?? []
    let inputTokens = summaries.reduce(0) { $0 + $1.inputTokens }
    let cacheTokens = summaries.reduce(0) { $0 + $1.cacheReadTokens }
    let outputTokens = summaries.reduce(0) { $0 + $1.outputTokens }
    let maxValue = max(inputTokens, cacheTokens, outputTokens, 1)

    structureStack.addArrangedSubview(
      DeskStatRowView(
        title: Copy.dashboardInput,
        value: TokenCostFormatting.tokenCount(inputTokens),
        fraction: Double(inputTokens) / Double(maxValue),
        tint: Desk.accent
      )
    )
    structureStack.addArrangedSubview(
      DeskStatRowView(
        title: Copy.dashboardCache,
        value: TokenCostFormatting.tokenCount(cacheTokens),
        fraction: Double(cacheTokens) / Double(maxValue),
        tint: Desk.green
      )
    )
    structureStack.addArrangedSubview(
      DeskStatRowView(
        title: Copy.dashboardOutput,
        value: TokenCostFormatting.tokenCount(outputTokens),
        fraction: Double(outputTokens) / Double(maxValue),
        tint: Desk.yellow
      )
    )
  }

  private func renderDailyTable(snapshot: TokenCostSnapshot, rangeDays: Int) {
    clearArrangedSubviews(tableRowsStack)

    let rows = filteredDailyEntries(snapshot: snapshot, rangeDays: rangeDays)
      .filter { ($0.totalTokens ?? 0) > 0 }
      .suffix(10)
      .reversed()

    if rows.isEmpty {
      tableRowsStack.addArrangedSubview(makePlaceholderLabel(Copy.dashboardNoRows))
      return
    }

    for entry in rows {
      tableRowsStack.addArrangedSubview(makeDailyRow(entry))
    }
  }

  private func makeDailyRow(_ entry: TokenCostDailyEntry) -> NSView {
    let dominantModel = entry.modelBreakdowns?.first?.modelName ?? Copy.dashboardNoDataPlaceholder
    let values = [entry.date, usd(entry.costUSD), tokenCount(entry.inputTokens), tokenCount(entry.cacheReadTokens), tokenCount(entry.outputTokens), dominantModel]
    let widths: [CGFloat] = [112, 92, 106, 106, 106, 186]
    let row = DeskLedgerRowView()
    for (index, value) in values.enumerated() {
      let label = makeLedgerLabel(value, bold: false, alignRight: index == 5)
      label.widthAnchor.constraint(equalToConstant: widths[index]).isActive = true
      label.textColor = index == 5 ? Desk.textPrimary : Desk.textSecondary
      row.stack.addArrangedSubview(label)
    }
    return row
  }

  private func renderNarrative(_ narrative: TokenCostNarrative) {
    renderNarrativeItems(narrative.whatChanged, into: whatChangedStack, fallback: Copy.dashboardNoNarrative)
    renderNarrativeItems(narrative.whatHelped, into: whatHelpedStack, fallback: Copy.dashboardNoNarrative)
    renderNarrativeItems(narrative.whatToWatch, into: whatToWatchStack, fallback: Copy.dashboardNoNarrative)
  }

  private func renderNarrativeItems(_ items: [String], into stack: NSStackView, fallback: String) {
    clearArrangedSubviews(stack)
    let source = items.isEmpty ? [fallback] : items
    for item in source {
      let label = NSTextField(wrappingLabelWithString: "• \(item)")
      label.font = .systemFont(ofSize: 12, weight: .medium)
      label.textColor = Desk.textSecondary
      stack.addArrangedSubview(label)
    }
  }

  private func filteredDailyEntries(snapshot: TokenCostSnapshot, rangeDays: Int) -> [TokenCostDailyEntry] {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    let calendar = Calendar.current
    let startDate = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: snapshot.updatedAt) ?? snapshot.updatedAt
    let startKey = formatter.string(from: startDate)
    return snapshot.daily.filter { $0.date >= startKey }
  }

  private func buildTimelinePoints(snapshot: TokenCostSnapshot, rangeDays: Int) -> [DeskDayPoint] {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    let calendar = Calendar.current
    let filtered = Dictionary(uniqueKeysWithValues: filteredDailyEntries(snapshot: snapshot, rangeDays: rangeDays).map { ($0.date, $0) })

    return (0..<rangeDays).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: -(rangeDays - 1 - offset), to: snapshot.updatedAt) else {
        return nil
      }
      let key = formatter.string(from: date)
      let entry = filtered[key]
      let dayNumber = calendar.component(.day, from: date)
      return DeskDayPoint(
        label: String(format: "%02d", dayNumber),
        costUSD: entry?.costUSD ?? 0,
        tokens: entry?.totalTokens ?? 0
      )
    }
  }

  private func timelineSummary(window: TokenCostWindowSummary?) -> String {
    guard let window else { return Copy.dashboardNoNarrative }
    let totalCost = usd(window.totalCostUSD)
    let totalTokens = tokenCount(window.totalTokens)
    let activeDays = window.activeDayCount
    return "\(window.windowDays)D total \(totalCost) · \(totalTokens) · \(activeDays) active days"
  }

  private func headerSummary(window: TokenCostWindowSummary?) -> String {
    guard let window else { return Copy.dashboardNoNarrative }
    let scope = Copy.costScopeSummary(
      isMerged: latestSnapshot?.source?.mode == .iCloudMerged,
      syncedDevices: latestSnapshot?.source?.syncedDeviceCount
    )
    return "\(scope) · \(selectedRange.days) day reading window · \(window.activeDayCount) active days · dominant \(window.dominantModelName ?? Copy.dashboardNoDataPlaceholder)"
  }

  private func clearArrangedSubviews(_ stack: NSStackView) {
    stack.arrangedSubviews.forEach {
      stack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
  }

  private func makePlaceholderLabel(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.textColor = Desk.textMuted
    return label
  }

  private func makeLedgerLabel(_ text: String, bold: Bool, alignRight: Bool) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = bold
      ? .monospacedSystemFont(ofSize: 10, weight: .bold)
      : .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    label.textColor = bold ? Desk.textMuted : Desk.textSecondary
    label.alignment = alignRight ? .right : .left
    return label
  }

  private func timestampString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = .current
    return formatter.string(from: date)
  }

  private func usd(_ value: Double?) -> String {
    guard let value else { return Copy.dashboardNoDataPlaceholder }
    return TokenCostFormatting.usd(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
  }

  private func tokenCount(_ value: Int?) -> String {
    guard let value else { return Copy.dashboardNoDataPlaceholder }
    return TokenCostFormatting.tokenCount(value)
  }

  private func percent(_ value: Double?) -> String {
    guard let value else { return Copy.dashboardNoDataPlaceholder }
    return "\(Int((value * 100).rounded()))%"
  }

  private func averageDaily(_ value: Double?) -> String {
    guard let value else { return Copy.dashboardNoDataPlaceholder }
    return "\(TokenCostFormatting.usd(value, minimumFractionDigits: 2, maximumFractionDigits: 2)) / day"
  }

  @objc private func rangeChanged() {
    selectedRange = RangeSelection(rawValue: rangeControl.selectedSegment) ?? .thirty
    renderContent()
  }

  @objc private func refreshTapped() {
    Task {
      await monitor.refresh(manual: true)
    }
  }

  @objc private func copyJSONTapped() {
    guard let snapshot = latestSnapshot,
          let data = try? TokenCostCLIReport.jsonData(snapshot: snapshot),
          let string = String(data: data, encoding: .utf8)
    else {
      return
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
  }
}

private final class DeskCardView: NSView {
  let titleLabel = NSTextField(labelWithString: "")
  let subtitleLabel = NSTextField(labelWithString: "")
  let contentStack = NSStackView()

  init(title: String) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = Desk.card.cgColor
    layer?.cornerRadius = Desk.radius
    layer?.borderWidth = 1
    layer?.borderColor = Desk.border.cgColor
    layer?.shadowColor = NSColor.black.withAlphaComponent(0.24).cgColor
    layer?.shadowOpacity = 1
    layer?.shadowRadius = 18
    layer?.shadowOffset = CGSize(width: 0, height: -2)
    translatesAutoresizingMaskIntoConstraints = false

    titleLabel.stringValue = title
    titleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
    titleLabel.textColor = Desk.textMuted
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
    subtitleLabel.textColor = Desk.textMuted
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.isHidden = true

    contentStack.orientation = .vertical
    contentStack.spacing = 12
    contentStack.alignment = .leading
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(titleLabel)
    addSubview(subtitleLabel)
    addSubview(contentStack)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Desk.cardPadding),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Desk.cardPadding),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Desk.cardPadding),

      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Desk.cardPadding),
      subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Desk.cardPadding),

      contentStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 10),
      contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Desk.cardPadding),
      contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Desk.cardPadding),
      contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Desk.cardPadding),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }
}

private final class DeskFlippedView: NSView {
  override var isFlipped: Bool { true }
}

private final class DeskMetricCardView: NSView {
  private let titleLabel = NSTextField(labelWithString: "")
  private let valueLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = Desk.cardAlt.cgColor
    layer?.cornerRadius = 18
    layer?.borderWidth = 1
    layer?.borderColor = Desk.border.cgColor
    translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
    titleLabel.textColor = Desk.textMuted
    valueLabel.font = .monospacedDigitSystemFont(ofSize: 27, weight: .bold)
    valueLabel.textColor = Desk.textPrimary
    detailLabel.font = .systemFont(ofSize: 12, weight: .medium)
    detailLabel.textColor = Desk.textSecondary

    [titleLabel, valueLabel, detailLabel].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 118),
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

      valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),

      detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      detailLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 8),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  func configure(title: String, value: String, detail: String) {
    titleLabel.stringValue = title
    valueLabel.stringValue = value
    detailLabel.stringValue = detail
  }
}

private final class DeskMiniMetricRowView: NSView {
  init(title: String, value: String) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = Desk.cardAlt.withAlphaComponent(0.72).cgColor
    layer?.cornerRadius = 12
    translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = NSTextField(labelWithString: title.uppercased())
    titleLabel.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
    titleLabel.textColor = Desk.textMuted

    let valueLabel = NSTextField(labelWithString: value)
    valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
    valueLabel.textColor = Desk.textPrimary
    valueLabel.alignment = .right

    [titleLabel, valueLabel].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 34),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
      valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }
}

private final class DeskLedgerRowView: NSView {
  let stack = NSStackView()

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = Desk.cardAlt.withAlphaComponent(0.42).cgColor
    layer?.cornerRadius = 12
    translatesAutoresizingMaskIntoConstraints = false

    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 36),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }
}

private struct DeskDayPoint {
  let label: String
  let costUSD: Double
  let tokens: Int
}

private final class DeskTimelineChartView: NSView {
  var points: [DeskDayPoint] = [] {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    Desk.cardAlt.setFill()
    dirtyRect.fill()

    guard !points.isEmpty else { return }

    let insetRect = dirtyRect.insetBy(dx: 16, dy: 18)
    guard insetRect.width > 0, insetRect.height > 0 else { return }
    let maxCost = max(points.map(\.costUSD).max() ?? 0, 0.001)
    let maxTokens = max(Double(points.map(\.tokens).max() ?? 0), 1)

    let gridPath = NSBezierPath()
    for idx in 0...3 {
      let y = insetRect.minY + (CGFloat(idx) / 3.0) * insetRect.height
      gridPath.move(to: CGPoint(x: insetRect.minX, y: y))
      gridPath.line(to: CGPoint(x: insetRect.maxX, y: y))
    }
    Desk.border.setStroke()
    gridPath.lineWidth = 1
    gridPath.stroke()

    let costPath = NSBezierPath()
    let tokenPath = NSBezierPath()
    let fillPath = NSBezierPath()
    let stepX = points.count > 1 ? insetRect.width / CGFloat(points.count - 1) : 0

    for (index, point) in points.enumerated() {
      let x = insetRect.minX + CGFloat(index) * stepX
      let costY = insetRect.minY + CGFloat(point.costUSD / maxCost) * insetRect.height
      let tokenY = insetRect.minY + CGFloat(Double(point.tokens) / maxTokens) * insetRect.height
      let pointRect = CGRect(x: x - 2, y: insetRect.minY, width: 4, height: costY - insetRect.minY)
      Desk.accentSoft.setFill()
      pointRect.fill()

      let costPoint = CGPoint(x: x, y: costY)
      let tokenPoint = CGPoint(x: x, y: tokenY)

      if index == 0 {
        costPath.move(to: costPoint)
        tokenPath.move(to: tokenPoint)
        fillPath.move(to: CGPoint(x: x, y: insetRect.minY))
        fillPath.line(to: costPoint)
      } else {
        costPath.line(to: costPoint)
        tokenPath.line(to: tokenPoint)
        fillPath.line(to: costPoint)
      }

      let label = NSString(string: point.label)
      label.draw(
        at: CGPoint(x: x - 8, y: insetRect.minY - 16),
        withAttributes: [
          .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
          .foregroundColor: Desk.textMuted,
        ]
      )
    }

    if let lastPoint = points.indices.last.map({ insetRect.minX + CGFloat($0) * stepX }) {
      fillPath.line(to: CGPoint(x: lastPoint, y: insetRect.minY))
      fillPath.close()
      Desk.accentSoft.setFill()
      fillPath.fill()
    }

    Desk.accent.setStroke()
    costPath.lineWidth = 2.5
    costPath.stroke()

    Desk.green.setStroke()
    tokenPath.lineWidth = 1.5
    var dashPattern: [CGFloat] = [4, 4]
    tokenPath.setLineDash(&dashPattern, count: dashPattern.count, phase: 0)
    tokenPath.stroke()
  }
}

private final class DeskHeatmapView: NSView {
  var entries: [TokenCostHourlyEntry] = [] {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    Desk.cardAlt.setFill()
    dirtyRect.fill()

    guard dirtyRect.width > 0, dirtyRect.height > 0 else { return }

    let normalized = Dictionary(uniqueKeysWithValues: entries.map { ($0.hour, $0) })
    let maxCost = max(entries.compactMap(\.costUSD).max() ?? 0, 0.001)
    let columns = 6
    let rows = 4
    let gap: CGFloat = 8
    let cellWidth = (dirtyRect.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
    let cellHeight = (dirtyRect.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
    guard cellWidth > 0, cellHeight > 0 else { return }

    for hour in 0..<24 {
      let row = hour / columns
      let column = hour % columns
      let x = CGFloat(column) * (cellWidth + gap)
      let y = dirtyRect.height - CGFloat(row + 1) * cellHeight - CGFloat(row) * gap
      let rect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
      let cost = normalized[hour]?.costUSD ?? 0
      let intensity = CGFloat(cost / maxCost)
      let cellColor = Desk.accent.blended(withFraction: 1 - intensity, of: Desk.cardAlt) ?? Desk.cardAlt
      cellColor.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()

      let label = NSString(string: String(format: "%02d", hour))
      label.draw(
        in: rect.insetBy(dx: 8, dy: 8),
        withAttributes: [
          .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
          .foregroundColor: Desk.textPrimary,
        ]
      )
    }
  }
}

private final class DeskAlertView: NSView {
  init(alert: TokenCostInsight) {
    super.init(frame: .zero)
    wantsLayer = true
    let tint: NSColor
    switch alert.severity {
    case "positive": tint = Desk.green
    case "warning": tint = Desk.yellow
    default: tint = Desk.accent
    }

    layer?.backgroundColor = tint.withAlphaComponent(0.12).cgColor
    layer?.cornerRadius = 14
    layer?.borderWidth = 1
    layer?.borderColor = tint.withAlphaComponent(0.24).cgColor
    translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = NSTextField(labelWithString: alert.title)
    titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
    titleLabel.textColor = Desk.textPrimary

    let messageLabel = NSTextField(wrappingLabelWithString: alert.message)
    messageLabel.font = .systemFont(ofSize: 11, weight: .medium)
    messageLabel.textColor = Desk.textSecondary

    [titleLabel, messageLabel].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
      messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }
}

private final class DeskLeaderboardRowView: NSView {
  init(title: String, subtitle: String, fraction: Double) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
    titleLabel.textColor = Desk.textPrimary

    let subtitleLabel = NSTextField(labelWithString: subtitle)
    subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
    subtitleLabel.textColor = Desk.textSecondary

    let track = NSView()
    track.wantsLayer = true
    track.layer?.backgroundColor = Desk.cardAlt.cgColor
    track.layer?.cornerRadius = 4
    track.translatesAutoresizingMaskIntoConstraints = false

    let fill = NSView()
    fill.wantsLayer = true
    fill.layer?.backgroundColor = Desk.accent.cgColor
    fill.layer?.cornerRadius = 4
    fill.translatesAutoresizingMaskIntoConstraints = false
    track.addSubview(fill)

    [titleLabel, subtitleLabel, track].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

      track.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
      track.leadingAnchor.constraint(equalTo: leadingAnchor),
      track.trailingAnchor.constraint(equalTo: trailingAnchor),
      track.heightAnchor.constraint(equalToConstant: 8),
      track.bottomAnchor.constraint(equalTo: bottomAnchor),

      fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
      fill.topAnchor.constraint(equalTo: track.topAnchor),
      fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
      fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: max(0.06, min(1, fraction))),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }
}

private final class DeskStatRowView: NSView {
  init(title: String, value: String, fraction: Double, tint: NSColor) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
    titleLabel.textColor = Desk.textPrimary

    let valueLabel = NSTextField(labelWithString: value)
    valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
    valueLabel.textColor = tint

    let track = NSView()
    track.wantsLayer = true
    track.layer?.backgroundColor = Desk.cardAlt.cgColor
    track.layer?.cornerRadius = 5
    track.translatesAutoresizingMaskIntoConstraints = false

    let fill = NSView()
    fill.wantsLayer = true
    fill.layer?.backgroundColor = tint.cgColor
    fill.layer?.cornerRadius = 5
    fill.translatesAutoresizingMaskIntoConstraints = false
    track.addSubview(fill)

    [titleLabel, valueLabel, track].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

      valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
      valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

      track.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 8),
      track.leadingAnchor.constraint(equalTo: leadingAnchor),
      track.trailingAnchor.constraint(equalTo: trailingAnchor),
      track.heightAnchor.constraint(equalToConstant: 10),
      track.bottomAnchor.constraint(equalTo: bottomAnchor),

      fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
      fill.topAnchor.constraint(equalTo: track.topAnchor),
      fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
      fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: max(0.06, min(1, fraction))),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }
}
