import AppKit
import CodexRateKit

private enum ShareDesk {
  static let previewTop = NSColor(srgbRed: 0.023, green: 0.043, blue: 0.071, alpha: 1)
  static let previewBottom = NSColor(srgbRed: 0.015, green: 0.024, blue: 0.044, alpha: 1)
  static let cardTop = NSColor(srgbRed: 0.056, green: 0.093, blue: 0.142, alpha: 1)
  static let cardBottom = NSColor(srgbRed: 0.028, green: 0.046, blue: 0.079, alpha: 1)
  static let panel = NSColor(srgbRed: 0.064, green: 0.101, blue: 0.149, alpha: 0.96)
  static let panelAlt = NSColor(srgbRed: 0.042, green: 0.072, blue: 0.114, alpha: 0.98)
  static let panelSoft = NSColor(srgbRed: 0.083, green: 0.125, blue: 0.181, alpha: 0.72)
  static let border = NSColor(srgbRed: 0.164, green: 0.226, blue: 0.310, alpha: 1)
  static let borderStrong = NSColor(srgbRed: 0.236, green: 0.338, blue: 0.446, alpha: 1)
  static let textPrimary = NSColor(srgbRed: 0.936, green: 0.953, blue: 0.982, alpha: 1)
  static let textSecondary = NSColor(srgbRed: 0.705, green: 0.782, blue: 0.860, alpha: 1)
  static let textMuted = NSColor(srgbRed: 0.461, green: 0.545, blue: 0.636, alpha: 1)
  static let accent = NSColor(srgbRed: 0.458, green: 0.742, blue: 0.968, alpha: 1)
  static let accentSoft = NSColor(srgbRed: 0.458, green: 0.742, blue: 0.968, alpha: 0.14)
  static let green = NSColor(srgbRed: 0.322, green: 0.851, blue: 0.581, alpha: 1)
  static let yellow = NSColor(srgbRed: 0.988, green: 0.789, blue: 0.255, alpha: 1)
  static let orange = NSColor(srgbRed: 0.988, green: 0.610, blue: 0.318, alpha: 1)

  static let previewSize = NSSize(width: 1_040, height: 760)
  static let cardSize = NSSize(width: 960, height: 592)
  static let contentWidth: CGFloat = 888
}

final class TokenCostSharePreviewViewController: NSViewController {
  private let statusLabel = NSTextField(labelWithString: Copy.costSharePreviewTitle)
  private let copyButton = NSButton()
  private let cardView: TokenCostShareCardView
  private var statusLabelCenterYConstraint: NSLayoutConstraint?

  init(snapshot: TokenCostSnapshot) {
    self.cardView = TokenCostShareCardView(snapshot: snapshot)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override func loadView() {
    view = TokenCostSharePreviewBackdropView(frame: NSRect(origin: .zero, size: ShareDesk.previewSize))
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    preferredContentSize = ShareDesk.previewSize
    buildLayout()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    alignStatusLabelToButtonTitle()
  }

  internal func renderImageForTesting() -> NSImage? {
    cardView.snapshotImage()
  }

  private func buildLayout() {
    statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    statusLabel.textColor = ShareDesk.textSecondary
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    copyButton.title = Copy.costShareCopyImage
    copyButton.isBordered = false
    copyButton.bezelStyle = .texturedRounded
    copyButton.font = .systemFont(ofSize: 12, weight: .semibold)
    copyButton.contentTintColor = ShareDesk.textPrimary
    copyButton.wantsLayer = true
    copyButton.layer?.backgroundColor = ShareDesk.accentSoft.cgColor
    copyButton.layer?.cornerRadius = 12
    copyButton.target = self
    copyButton.action = #selector(copyImageTapped)
    copyButton.translatesAutoresizingMaskIntoConstraints = false

    [statusLabel, copyButton, cardView].forEach(view.addSubview)
    cardView.translatesAutoresizingMaskIntoConstraints = false

    statusLabelCenterYConstraint = statusLabel.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor)

    NSLayoutConstraint.activate([
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      statusLabelCenterYConstraint!,

      copyButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
      copyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      copyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 116),
      copyButton.heightAnchor.constraint(equalToConstant: 38),

      cardView.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 18),
      cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      cardView.widthAnchor.constraint(equalToConstant: ShareDesk.cardSize.width),
      cardView.heightAnchor.constraint(equalToConstant: ShareDesk.cardSize.height),
    ])
  }

  private func alignStatusLabelToButtonTitle() {
    guard let statusLabelCenterYConstraint,
          let cell = copyButton.cell as? NSButtonCell
    else {
      return
    }

    let titleRect = cell.titleRect(forBounds: copyButton.bounds)
    let titleMidY = copyButton.frame.minY + titleRect.midY
    let buttonMidY = copyButton.frame.midY
    let targetOffset = titleMidY - buttonMidY

    if abs(statusLabelCenterYConstraint.constant - targetOffset) > 0.1 {
      statusLabelCenterYConstraint.constant = targetOffset
    }
  }

  @objc private func copyImageTapped() {
    guard let image = cardView.snapshotImage(), copyImageToPasteboard(image) else {
      return
    }

    statusLabel.stringValue = Copy.costShareCopied
  }

  private func copyImageToPasteboard(_ image: NSImage) -> Bool {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
      return false
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setData(pngData, forType: .png)
    pasteboard.setData(tiffData, forType: .tiff)
    return true
  }
}

private final class TokenCostSharePreviewBackdropView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    NSGradient(starting: ShareDesk.previewTop, ending: ShareDesk.previewBottom)?
      .draw(in: bounds, angle: -90)

    ShareDesk.accent.withAlphaComponent(0.08).setFill()
    NSBezierPath(ovalIn: CGRect(x: 42, y: bounds.maxY - 230, width: 240, height: 240)).fill()

    ShareDesk.green.withAlphaComponent(0.05).setFill()
    NSBezierPath(ovalIn: CGRect(x: bounds.maxX - 300, y: 32, width: 220, height: 220)).fill()
  }
}

private final class TokenCostShareCardView: NSView {
  private let snapshot: TokenCostSnapshot

  private let contentStack = NSStackView()
  private let headerRow = NSStackView()
  private let headerMetaRow = NSStackView()
  private let badgeView = TokenCostShareChipView(
    text: Copy.costShareBrand.uppercased(),
    textColor: ShareDesk.accent,
    fillColor: ShareDesk.accentSoft,
    font: .monospacedSystemFont(ofSize: 12, weight: .bold)
  )
  private let updatedLabel = NSTextField(labelWithString: "")
  private let partialBadgeView = TokenCostShareChipView(
    text: Copy.dashboardPartialPricing,
    textColor: ShareDesk.yellow,
    fillColor: ShareDesk.yellow.withAlphaComponent(0.14),
    font: .systemFont(ofSize: 11, weight: .bold)
  )

  private let windowRow = NSStackView()
  private let currentWindowView = TokenCostShareWindowCardView()
  private let weekWindowView = TokenCostShareWindowCardView()
  private let monthWindowView = TokenCostShareWindowCardView()

  private let chartCard = NSView()
  private let chartHeaderRow = NSStackView()
  private let chartTitleLabel = NSTextField(labelWithString: "Burn Pattern")
  private let chartSummaryLabel = NSTextField(labelWithString: "")
  private let chartView = TokenCostShareBarChartView()

  init(snapshot: TokenCostSnapshot) {
    self.snapshot = snapshot
    super.init(frame: NSRect(origin: .zero, size: ShareDesk.cardSize))
    wantsLayer = true
    layer?.cornerRadius = 32
    layer?.shadowColor = NSColor.black.withAlphaComponent(0.30).cgColor
    layer?.shadowOpacity = 1
    layer?.shadowRadius = 24
    layer?.shadowOffset = CGSize(width: 0, height: -4)
    translatesAutoresizingMaskIntoConstraints = false
    buildLayout()
    renderSnapshot()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var intrinsicContentSize: NSSize {
    ShareDesk.cardSize
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let outerRect = bounds.insetBy(dx: 1, dy: 1)
    let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 32, yRadius: 32)
    NSGradient(starting: ShareDesk.cardTop, ending: ShareDesk.cardBottom)?
      .draw(in: outerPath, angle: -90)

    ShareDesk.border.setStroke()
    outerPath.lineWidth = 1
    outerPath.stroke()

    let accentRect = CGRect(
      x: outerRect.minX + 30,
      y: outerRect.maxY - 22,
      width: outerRect.width - 60,
      height: 4
    )
    let accentPath = NSBezierPath(roundedRect: accentRect, xRadius: 2, yRadius: 2)
    if let accentGradient = NSGradient(colors: [
      ShareDesk.accent.withAlphaComponent(0.70),
      ShareDesk.green.withAlphaComponent(0.55),
    ]) {
      accentGradient.draw(in: accentPath, angle: 0)
    }

    ShareDesk.accent.withAlphaComponent(0.06).setFill()
    NSBezierPath(ovalIn: CGRect(x: 42, y: bounds.maxY - 256, width: 220, height: 220)).fill()
  }

  func snapshotImage() -> NSImage? {
    layoutSubtreeIfNeeded()
    guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
      return nil
    }

    cacheDisplay(in: bounds, to: representation)
    let image = NSImage(size: bounds.size)
    image.addRepresentation(representation)
    return image
  }

  private func buildLayout() {
    contentStack.orientation = .vertical
    contentStack.spacing = 22
    contentStack.alignment = .leading
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    updatedLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    updatedLabel.textColor = ShareDesk.textSecondary
    updatedLabel.translatesAutoresizingMaskIntoConstraints = false

    partialBadgeView.isHidden = true

    headerRow.orientation = .horizontal
    headerRow.alignment = .centerY
    headerRow.distribution = .fill
    headerRow.translatesAutoresizingMaskIntoConstraints = false

    headerMetaRow.orientation = .horizontal
    headerMetaRow.alignment = .centerY
    headerMetaRow.spacing = 10
    headerMetaRow.translatesAutoresizingMaskIntoConstraints = false
    headerMetaRow.setContentHuggingPriority(.required, for: .horizontal)
    headerMetaRow.addArrangedSubview(updatedLabel)
    headerMetaRow.addArrangedSubview(partialBadgeView)

    headerRow.addArrangedSubview(badgeView)
    headerRow.addArrangedSubview(headerMetaRow)

    windowRow.orientation = .horizontal
    windowRow.alignment = .top
    windowRow.distribution = .fillEqually
    windowRow.spacing = 12
    windowRow.translatesAutoresizingMaskIntoConstraints = false
    windowRow.addArrangedSubview(currentWindowView)
    windowRow.addArrangedSubview(weekWindowView)
    windowRow.addArrangedSubview(monthWindowView)

    chartCard.wantsLayer = true
    chartCard.layer?.backgroundColor = ShareDesk.panelAlt.cgColor
    chartCard.layer?.cornerRadius = 26
    chartCard.layer?.borderWidth = 1
    chartCard.layer?.borderColor = ShareDesk.borderStrong.withAlphaComponent(0.72).cgColor
    chartCard.translatesAutoresizingMaskIntoConstraints = false

    chartHeaderRow.orientation = .horizontal
    chartHeaderRow.alignment = .centerY
    chartHeaderRow.distribution = .fill
    chartHeaderRow.spacing = 12
    chartHeaderRow.translatesAutoresizingMaskIntoConstraints = false

    chartTitleLabel.font = .systemFont(ofSize: 15, weight: .bold)
    chartTitleLabel.textColor = ShareDesk.textPrimary
    chartTitleLabel.translatesAutoresizingMaskIntoConstraints = false

    chartSummaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
    chartSummaryLabel.textColor = ShareDesk.textSecondary
    chartSummaryLabel.alignment = .right
    chartSummaryLabel.lineBreakMode = .byTruncatingTail
    chartSummaryLabel.maximumNumberOfLines = 1
    chartSummaryLabel.translatesAutoresizingMaskIntoConstraints = false

    chartHeaderRow.addArrangedSubview(chartTitleLabel)
    chartHeaderRow.addArrangedSubview(chartSummaryLabel)

    chartView.translatesAutoresizingMaskIntoConstraints = false

    chartCard.addSubview(chartHeaderRow)
    chartCard.addSubview(chartView)

    NSLayoutConstraint.activate([
      chartHeaderRow.topAnchor.constraint(equalTo: chartCard.topAnchor, constant: 18),
      chartHeaderRow.leadingAnchor.constraint(equalTo: chartCard.leadingAnchor, constant: 18),
      chartHeaderRow.trailingAnchor.constraint(equalTo: chartCard.trailingAnchor, constant: -18),

      chartView.topAnchor.constraint(equalTo: chartHeaderRow.bottomAnchor, constant: 14),
      chartView.leadingAnchor.constraint(equalTo: chartCard.leadingAnchor, constant: 18),
      chartView.trailingAnchor.constraint(equalTo: chartCard.trailingAnchor, constant: -18),
      chartView.bottomAnchor.constraint(equalTo: chartCard.bottomAnchor, constant: -18),
      chartView.heightAnchor.constraint(equalToConstant: 252),
    ])

    addSubview(contentStack)
    contentStack.addArrangedSubview(headerRow)
    contentStack.addArrangedSubview(windowRow)
    contentStack.addArrangedSubview(chartCard)

    NSLayoutConstraint.activate([
      badgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 158),
      badgeView.heightAnchor.constraint(equalToConstant: 28),

      partialBadgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 112),
      partialBadgeView.heightAnchor.constraint(equalToConstant: 26),

      headerRow.widthAnchor.constraint(equalToConstant: ShareDesk.contentWidth),
      windowRow.widthAnchor.constraint(equalToConstant: ShareDesk.contentWidth),
      chartCard.widthAnchor.constraint(equalToConstant: ShareDesk.contentWidth),
      currentWindowView.heightAnchor.constraint(equalToConstant: 148),
      weekWindowView.heightAnchor.constraint(equalToConstant: 148),
      monthWindowView.heightAnchor.constraint(equalToConstant: 148),

      contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 34),
      contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
      contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
      contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -34),
    ])
  }

  private func renderSnapshot() {
    let window7 = snapshot.windowSummary(days: 7)
    let window30 = snapshot.windowSummary(days: 30)
    let hottestEntry = snapshot.daily
      .suffix(30)
      .max { ($0.totalTokens ?? 0) < ($1.totalTokens ?? 0) }
    let isMerged = snapshot.source?.mode == .iCloudMerged

    partialBadgeView.isHidden = !snapshot.hasPartialPricing
    updatedLabel.stringValue = "Updated \(formattedTimestamp(snapshot.updatedAt))"

    currentWindowView.configure(
      title: "CURRENT",
      value: formattedTokensLabel(snapshot.todayTokens),
      metric: isMerged ? "All-device burn" : "Local session burn",
      detail: apiPricedSpendDetail(cost: snapshot.todayCostUSD),
      accent: ShareDesk.green
    )

    weekWindowView.configure(
      title: "7D",
      value: formattedTokensLabel(snapshot.last7DaysTokens),
      metric: averageTokensSummary(window: window7),
      detail: apiPricedSpendDetail(cost: snapshot.last7DaysCostUSD, activeDays: window7?.activeDayCount),
      accent: ShareDesk.accent
    )

    monthWindowView.configure(
      title: "30D",
      value: formattedTokensLabel(snapshot.last30DaysTokens),
      metric: averageTokensSummary(window: window30),
      detail: apiPricedSpendDetail(cost: snapshot.last30DaysCostUSD, activeDays: window30?.activeDayCount),
      accent: ShareDesk.yellow
    )

    chartSummaryLabel.stringValue = chartSummary(window: window30, hottestEntry: hottestEntry)
    chartView.entries = Array(snapshot.daily.suffix(30))
  }

  private func chartSummary(
    window: TokenCostWindowSummary?,
    hottestEntry: TokenCostDailyEntry?
  ) -> String {
    var parts: [String] = []

    if let averageTokens = window?.averageDailyTokens {
      parts.append("Avg \(formattedAverageTokens(averageTokens)) tokens / day")
    }

    if let average = window?.averageDailyCostUSD {
      parts.append("API priced \(formattedUSD(average)) / day")
    }

    if let hottestEntry, (hottestEntry.totalTokens ?? 0) > 0 {
      parts.append("Peak \(trimmedDate(hottestEntry.date)) \(formattedTokens(hottestEntry.totalTokens)) tokens")
    }

    if let activeDays = window?.activeDayCount {
      parts.append("\(activeDays) active days")
    }

    return parts.isEmpty ? "30-day token cost trend" : parts.joined(separator: " · ")
  }

  private func trimmedDate(_ value: String) -> String {
    let parts = value.split(separator: "-")
    guard parts.count == 3 else { return value }
    return "\(parts[1])-\(parts[2])"
  }

  private func formattedUSD(_ value: Double?) -> String {
    guard let value else { return "—" }
    return TokenCostFormatting.usd(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
  }

  private func formattedTokens(_ value: Int?) -> String {
    guard let value else { return "—" }
    return TokenCostFormatting.tokenCount(value)
  }

  private func formattedTokensLabel(_ value: Int?) -> String {
    guard value != nil else { return "—" }
    return "\(formattedTokens(value)) tokens"
  }

  private func formattedAverageTokens(_ value: Double?) -> String {
    guard let value else { return "—" }
    return TokenCostFormatting.tokenCount(Int(value.rounded()))
  }

  private func averageTokensSummary(window: TokenCostWindowSummary?) -> String {
    if let averageTokens = window?.averageDailyTokens {
      return "Avg/day \(formattedAverageTokens(averageTokens)) tokens"
    }

    if let activeDays = window?.activeDayCount {
      return "\(activeDays) active days"
    }

    return snapshot.source?.mode == .iCloudMerged ? "All-device token summary" : "Local token summary"
  }

  private func apiPricedSpendDetail(cost: Double?, activeDays: Int? = nil) -> String {
    var parts = ["API priced \(formattedUSD(cost))"]

    if let activeDays {
      parts.append("\(activeDays) active days")
    }

    return parts.joined(separator: " · ")
  }

  private func formattedTimestamp(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = .autoupdatingCurrent
    return formatter.string(from: value)
  }
}

private final class TokenCostShareWindowCardView: NSView {
  private let titleLabel = NSTextField(labelWithString: "")
  private let valueLabel = NSTextField(labelWithString: "")
  private let metricLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = ShareDesk.panel.cgColor
    layer?.cornerRadius = 22
    layer?.borderWidth = 1
    layer?.borderColor = ShareDesk.borderStrong.withAlphaComponent(0.72).cgColor
    translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
    titleLabel.textColor = ShareDesk.textMuted
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
    valueLabel.lineBreakMode = .byTruncatingTail
    valueLabel.maximumNumberOfLines = 1
    valueLabel.translatesAutoresizingMaskIntoConstraints = false

    metricLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    metricLabel.textColor = ShareDesk.textPrimary
    metricLabel.lineBreakMode = .byTruncatingTail
    metricLabel.maximumNumberOfLines = 1
    metricLabel.translatesAutoresizingMaskIntoConstraints = false

    detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
    detailLabel.textColor = ShareDesk.textSecondary
    detailLabel.lineBreakMode = .byTruncatingTail
    detailLabel.maximumNumberOfLines = 2
    detailLabel.translatesAutoresizingMaskIntoConstraints = false

    [titleLabel, valueLabel, metricLabel, detailLabel].forEach(addSubview)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

      valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

      metricLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 6),
      metricLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      metricLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

      detailLabel.topAnchor.constraint(equalTo: metricLabel.bottomAnchor, constant: 8),
      detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      bottomAnchor.constraint(greaterThanOrEqualTo: detailLabel.bottomAnchor, constant: 16),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  func configure(title: String, value: String, metric: String, detail: String, accent: NSColor) {
    titleLabel.stringValue = title
    valueLabel.stringValue = value
    valueLabel.textColor = accent
    metricLabel.stringValue = metric
    detailLabel.stringValue = detail
  }
}

private final class TokenCostShareChipView: NSView {
  let label: NSTextField

  init(text: String, textColor: NSColor, fillColor: NSColor, font: NSFont) {
    self.label = NSTextField(labelWithString: text)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = fillColor.cgColor
    layer?.cornerRadius = 10
    translatesAutoresizingMaskIntoConstraints = false

    label.font = font
    label.textColor = textColor
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.translatesAutoresizingMaskIntoConstraints = false

    addSubview(label)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }
}

private final class TokenCostShareBarChartView: NSView {
  var entries: [TokenCostDailyEntry] = [] {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let bounds = self.bounds
    guard bounds.width > 0, bounds.height > 0 else { return }

    let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18)
    ShareDesk.panel.withAlphaComponent(0.98).setFill()
    backgroundPath.fill()

    let insetRect = bounds.insetBy(dx: 14, dy: 16)
    let baseline = insetRect.minY + 14
    let maxHeight = insetRect.height - 28

    let gridPath = NSBezierPath()
    for index in 0...2 {
      let y = baseline + (CGFloat(index) / 2.0) * maxHeight
      gridPath.move(to: CGPoint(x: insetRect.minX, y: y))
      gridPath.line(to: CGPoint(x: insetRect.maxX, y: y))
    }
    ShareDesk.border.withAlphaComponent(0.42).setStroke()
    gridPath.lineWidth = 1
    gridPath.stroke()

    let labelAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
      .foregroundColor: ShareDesk.textMuted,
    ]
    NSString(string: "30D AGO").draw(
      at: CGPoint(x: insetRect.minX, y: insetRect.minY - 2),
      withAttributes: labelAttributes
    )

    let todayLabel = NSString(string: "TODAY")
    let todaySize = todayLabel.size(withAttributes: labelAttributes)
    todayLabel.draw(
      at: CGPoint(x: insetRect.maxX - todaySize.width, y: insetRect.minY - 2),
      withAttributes: labelAttributes
    )

    guard !entries.isEmpty else { return }

    let values = entries.map { Double(Swift.max($0.totalTokens ?? 0, 0)) }
    let maxValue = Swift.max(values.max() ?? 0, 1)
    let gap: CGFloat = entries.count > 18 ? 5 : 7
    let availableWidth = insetRect.width - gap * CGFloat(max(entries.count - 1, 0))
    let barWidth = max(10, availableWidth / CGFloat(entries.count))

    for (index, entry) in entries.enumerated() {
      let x = insetRect.minX + CGFloat(index) * (barWidth + gap)
      let value = Double(Swift.max(entry.totalTokens ?? 0, 0))
      let barHeight = Swift.max(8, CGFloat(value / maxValue) * maxHeight)
      let barRect = CGRect(x: x, y: baseline, width: barWidth, height: barHeight)

      let baseColor = value > 0
        ? ShareDesk.green.withAlphaComponent(index == entries.count - 1 ? 0.96 : 0.80)
        : ShareDesk.border.withAlphaComponent(0.48)
      baseColor.setFill()
      NSBezierPath(roundedRect: barRect, xRadius: 5, yRadius: 5).fill()

      if value > 0 {
        let capHeight = max(6, barRect.height * 0.28)
        let capRect = CGRect(
          x: barRect.minX,
          y: barRect.maxY - capHeight,
          width: barRect.width,
          height: capHeight
        )
        ShareDesk.accent.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: capRect, xRadius: 5, yRadius: 5).fill()
      }
    }
  }
}
