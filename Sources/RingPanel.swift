import AppKit

// The floating Liquid Glass panel: a ring of files around the hovered folder
// icon, or (after "+N") a scrollable grid of every file next to it.

final class RingPanel: NSObject, NSDraggingSource {
  private enum Mode { case ring, grid }

  private var panel: NSPanel?
  private var mode = Mode.ring
  private(set) var folder: URL?
  private(set) var iconFrame = CGRect.zero
  private var haloCenter = CGPoint.zero
  private var haloRadius: CGFloat = 0
  private var draggedURL: URL?

  private(set) var hoveredEntry: FileEntry?
  private weak var hoveredView: FileItemView?
  var isOpen: Bool { panel?.isVisible == true && folder != nil }
  var isDragging: Bool { draggedURL != nil }

  // MARK: Hit area

  /// Whether the pointer (AppKit screen coordinates) is over the open ring,
  /// the grid, or the folder icon itself.
  func contains(_ p: CGPoint) -> Bool {
    guard isOpen, let panel else { return false }
    if iconFrame.insetBy(dx: -8, dy: -8).contains(p) { return true }
    switch mode {
    case .ring: return panel.frame.contains(p) && hypot(p.x - haloCenter.x, p.y - haloCenter.y) <= haloRadius
    case .grid: return panel.frame.insetBy(dx: -8, dy: -8).contains(p)
    }
  }

  /// Highlights the single item under the pointer, if any.
  func updateHover(at p: CGPoint) {
    var item: FileItemView?
    if isOpen, let panel, let content = panel.contentView {
      var v = content.hitTest(content.convert(panel.convertPoint(fromScreen: p), from: nil))
      while let cur = v, !(cur is FileItemView) { v = cur.superview }
      item = v as? FileItemView
    }
    guard item !== hoveredView else { return }
    hoveredView?.setHovered(false)
    item?.setHovered(true)
    hoveredView = item
    hoveredEntry = item?.entry
  }

  // MARK: Ring

  func show(folder: URL, iconFrame: CGRect, animated: Bool = true) {
    self.folder = folder
    self.iconFrame = iconFrame
    mode = .ring
    hoveredEntry = nil
    hoveredView = nil

    let entries = readFolder(folder)
    let screen = screenFor(iconFrame)
    let bounds = screen.visibleFrame
    let center = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
    let layout = computeRingLayout(center: center, bounds: bounds, totalFiles: entries.count)
    haloCenter = center
    haloRadius = layout.haloRadius

    let haloRect = CGRect(x: center.x - haloRadius, y: center.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
    let frame = haloRect.intersection(bounds.union(iconFrame))
    let panel = makePanel(frame: frame)
    let root = panel.contentView!
    let local = { (p: CGPoint) in CGPoint(x: p.x - frame.minX, y: p.y - frame.minY) }

    let glass = NSGlassEffectView(frame: haloRect.offsetBy(dx: -frame.minX, dy: -frame.minY))
    glass.cornerRadius = haloRadius
    root.addSubview(glass)
    root.addSubview(folderIcon(folder, frame: iconFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)))

    if entries.isEmpty {
      let empty = NSTextField(labelWithString: "Empty")
      empty.font = .systemFont(ofSize: 12, weight: .medium)
      empty.textColor = .white.withAlphaComponent(0.85)
      empty.sizeToFit()
      let c = local(center)
      empty.frame.origin = CGPoint(x: c.x - empty.frame.width / 2, y: c.y - iconFrame.height / 2 - 26)
      root.addSubview(empty)
    }

    var views: [(NSView, CGPoint)] = []
    for (i, slot) in layout.slots.enumerated() {
      let view: NSView
      if i < layout.fileCount {
        view = itemView(entries[i])
      } else {
        let more = MoreView(count: entries.count - layout.fileCount)
        more.onClick = { [weak self] in self?.showGrid(entries) }
        view = more
      }
      root.addSubview(view)
      views.append((view, local(slot.center)))
    }

    let start = local(center)
    for (i, (view, target)) in views.enumerated() {
      let s = view.frame.size
      let final = CGRect(x: target.x - s.width / 2, y: target.y - s.height / 2, width: s.width, height: s.height)
      guard animated else { view.frame = final; continue }
      view.frame = CGRect(x: start.x - s.width / 2, y: start.y - s.height / 2, width: s.width, height: s.height)
      view.alphaValue = 0
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.02 * Double(i)) {
        NSAnimationContext.runAnimationGroup { ctx in
          ctx.duration = 0.35
          ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.35, 0.5, 1)
          ctx.allowsImplicitAnimation = true
          view.animator().frame = final
          view.animator().alphaValue = 1
        }
      }
    }
    present(panel, animated: animated)
  }

  // MARK: Grid

  private func showGrid(_ entries: [FileEntry]) {
    guard let folder else { return }
    mode = .grid
    hoveredEntry = nil
    hoveredView = nil

    let screen = screenFor(iconFrame)
    let bounds = screen.visibleFrame
    let cols = 4, cell = CGSize(width: 90, height: 100), pad: CGFloat = 14, header: CGFloat = 34
    let rows = Int(ceil(Double(entries.count) / Double(cols)))
    let docHeight = CGFloat(rows) * cell.height
    let width = CGFloat(cols) * cell.width + pad * 2
    let height = min(docHeight + header + pad * 2, bounds.height * 0.6)

    // Open toward the middle of the screen, next to the icon, clamped on screen.
    let toRight = iconFrame.midX < bounds.midX, toUp = iconFrame.midY < bounds.midY
    var x = toRight ? iconFrame.maxX + 8 : iconFrame.minX - 8 - width
    var y = toUp ? iconFrame.minY : iconFrame.maxY - height
    x = min(max(x, bounds.minX + 8), bounds.maxX - 8 - width)
    y = min(max(y, bounds.minY + 8), bounds.maxY - 8 - height)
    let frame = CGRect(x: x, y: y, width: width, height: height)

    let panel = makePanel(frame: frame)
    let root = panel.contentView!
    let glass = NSGlassEffectView(frame: root.bounds)
    glass.cornerRadius = 22
    root.addSubview(glass)

    let title = NSTextField(labelWithString: "\(folder.lastPathComponent)  ·  \(entries.count) items")
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    title.textColor = .white
    title.frame = CGRect(x: pad + 4, y: height - pad - 20, width: width - pad * 2, height: 18)
    root.addSubview(title)

    let scroll = NSScrollView(frame: CGRect(x: pad, y: pad, width: width - pad * 2, height: height - header - pad * 2))
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    let doc = FlippedView(frame: CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: docHeight))
    for (i, entry) in entries.enumerated() {
      let v = itemView(entry)
      v.frame.origin = CGPoint(x: CGFloat(i % cols) * cell.width + (cell.width - v.frame.width) / 2,
                               y: CGFloat(i / cols) * cell.height)
      doc.addSubview(v)
    }
    scroll.documentView = doc
    root.addSubview(scroll)
    present(panel, animated: true)
  }

  // MARK: Close

  func close(animated: Bool = true) {
    guard let panel else { return }
    folder = nil
    hoveredEntry = nil
    guard animated else { panel.orderOut(nil); return }
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.18
      panel.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      if self?.folder == nil { panel.orderOut(nil) }
    })
  }

  // MARK: Building blocks

  private func screenFor(_ rect: CGRect) -> NSScreen {
    let c = CGPoint(x: rect.midX, y: rect.midY)
    return NSScreen.screens.first { $0.frame.contains(c) } ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private func makePanel(frame: CGRect) -> NSPanel {
    let panel = self.panel ?? {
      let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      p.isFloatingPanel = true
      p.level = .floating
      p.backgroundColor = .clear
      p.isOpaque = false
      p.hasShadow = false
      p.hidesOnDeactivate = false
      p.becomesKeyOnlyIfNeeded = true
      p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
      self.panel = p
      return p
    }()
    panel.setFrame(frame, display: false)
    let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
    root.clipsToBounds = true
    panel.contentView = root
    return panel
  }

  private func present(_ panel: NSPanel, animated: Bool) {
    if !panel.isVisible || panel.alphaValue < 1 {
      panel.alphaValue = animated ? 0 : 1
      panel.orderFrontRegardless()
      if animated {
        NSAnimationContext.runAnimationGroup { ctx in
          ctx.duration = 0.2
          panel.animator().alphaValue = 1
        }
      }
    }
  }

  private func folderIcon(_ folder: URL, frame: CGRect) -> NSView {
    let v = ClickImageView(frame: frame)
    v.image = NSWorkspace.shared.icon(forFile: folder.path)
    v.imageScaling = .scaleProportionallyUpOrDown
    v.onClick = { [weak self] in
      NSWorkspace.shared.open(folder)
      self?.close()
    }
    return v
  }

  private func itemView(_ entry: FileEntry) -> FileItemView {
    let v = FileItemView(entry: entry)
    v.onClick = { [weak self] in
      NSWorkspace.shared.open(entry.url)
      self?.close()
    }
    v.onDragStart = { [weak self, weak v] event in
      guard let self, let v else { return }
      let item = NSDraggingItem(pasteboardWriter: entry.url as NSURL)
      item.setDraggingFrame(v.imageView.frame, contents: v.imageView.image)
      self.draggedURL = entry.url
      v.beginDraggingSession(with: [item], event: event, source: self)
    }
    return v
  }

  // MARK: NSDraggingSource

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    context == .outsideApplication ? [.copy, .move, .generic] : []
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    let dragged = draggedURL
    draggedURL = nil
    // A drop into Finder on the same disk moves the file; refresh so the ring
    // never shows a file that is gone.
    if let dragged, !FileManager.default.fileExists(atPath: dragged.path), let folder, isOpen {
      show(folder: folder, iconFrame: iconFrame, animated: false)
    }
  }
}

private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

private final class ClickImageView: NSImageView {
  var onClick: () -> Void = {}
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) { onClick() }
}
