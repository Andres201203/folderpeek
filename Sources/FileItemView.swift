import AppKit
import QuickLookThumbnailing

// One file on the ring or in the grid: icon (upgraded to a Quick Look
// thumbnail), name, hover highlight, click and drag. Hover is driven by
// RingPanel.updateHover so only one item can ever be highlighted.

final class FileItemView: NSView {
  static let size = CGSize(width: 84, height: 96)
  static let iconSize: CGFloat = 48

  let entry: FileEntry
  var onClick: () -> Void = {}
  var onDragStart: (NSEvent) -> Void = { _ in }

  let imageView = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private var downPoint: NSPoint?

  init(entry: FileEntry) {
    self.entry = entry
    super.init(frame: CGRect(origin: .zero, size: Self.size))
    wantsLayer = true

    imageView.image = NSWorkspace.shared.icon(forFile: entry.url.path)
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.frame = iconRect(scale: 1)
    imageView.shadow = shadow(blur: 6, alpha: 0.35)
    addSubview(imageView)

    label.stringValue = entry.name
    label.font = .systemFont(ofSize: 11, weight: .medium)
    label.textColor = .white
    label.alignment = .center
    label.maximumNumberOfLines = 2
    label.lineBreakMode = .byTruncatingMiddle
    label.cell?.truncatesLastVisibleLine = true
    label.wantsLayer = true
    label.layer?.cornerRadius = 5
    label.shadow = shadow(blur: 3, alpha: 0.7)
    addSubview(label)
    layoutLabel()

    if entry.isCloudPlaceholder {
      let badge = NSImageView(image: NSImage(systemSymbolName: "icloud.and.arrow.down", accessibilityDescription: "In iCloud")!)
      badge.contentTintColor = .white
      badge.frame = CGRect(x: imageView.frame.maxX - 14, y: imageView.frame.minY - 2, width: 16, height: 16)
      addSubview(badge)
    } else {
      loadThumbnail()
    }
  }

  required init?(coder: NSCoder) { fatalError() }

  private func iconRect(scale: CGFloat) -> CGRect {
    let s = Self.iconSize * scale
    return CGRect(x: (Self.size.width - s) / 2, y: Self.size.height - 6 - Self.iconSize / 2 - s / 2, width: s, height: s)
  }

  private func layoutLabel() {
    let fit = label.sizeThatFits(CGSize(width: Self.size.width - 4, height: 30))
    let w = min(fit.width + 10, Self.size.width)
    label.frame = CGRect(x: (Self.size.width - w) / 2, y: Self.size.height - 12 - Self.iconSize - fit.height,
                         width: w, height: fit.height)
  }

  private func shadow(blur: CGFloat, alpha: CGFloat) -> NSShadow {
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = CGSize(width: 0, height: -1)
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    return s
  }

  private func loadThumbnail() {
    let req = QLThumbnailGenerator.Request(
      fileAt: entry.url, size: CGSize(width: 96, height: 96),
      scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
    QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
      guard let image = rep?.nsImage else { return }
      DispatchQueue.main.async { self?.imageView.image = image }
    }
  }

  func setHovered(_ on: Bool) {
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.15
      ctx.allowsImplicitAnimation = true
      imageView.animator().frame = iconRect(scale: on ? 1.15 : 1)
    }
    label.layer?.backgroundColor = on ? NSColor.controlAccentColor.cgColor : nil
    label.shadow = on ? nil : shadow(blur: 3, alpha: 0.7)
  }

  // MARK: Mouse

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) { downPoint = event.locationInWindow }

  override func mouseDragged(with event: NSEvent) {
    guard let d = downPoint else { return }
    let p = event.locationInWindow
    if hypot(p.x - d.x, p.y - d.y) > 3 {
      downPoint = nil
      onDragStart(event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    if downPoint != nil { onClick() }
    downPoint = nil
  }
}

/// The "+N" bubble that swaps the ring for the full grid.
final class MoreView: NSView {
  var onClick: () -> Void = {}

  init(count: Int) {
    super.init(frame: CGRect(origin: .zero, size: FileItemView.size))
    let d: CGFloat = 46
    let glass = NSGlassEffectView(frame: CGRect(x: (bounds.width - d) / 2, y: bounds.height - 6 - FileItemView.iconSize / 2 - d / 2, width: d, height: d))
    glass.cornerRadius = d / 2
    let n = NSTextField(labelWithString: "+\(count)")
    n.font = .systemFont(ofSize: 14, weight: .semibold)
    n.textColor = .white
    n.alignment = .center
    n.sizeToFit()
    n.frame.origin = CGPoint(x: (d - n.frame.width) / 2, y: (d - n.frame.height) / 2)
    glass.contentView = NSView(frame: glass.bounds)
    glass.contentView?.addSubview(n)
    addSubview(glass)

    let label = NSTextField(labelWithString: "See all")
    label.font = .systemFont(ofSize: 11, weight: .medium)
    label.textColor = .white
    label.alignment = .center
    label.frame = CGRect(x: 0, y: glass.frame.minY - 20, width: bounds.width, height: 15)
    addSubview(label)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseUp(with event: NSEvent) { onClick() }
}
