import AppKit
import ApplicationServices
import Quartz

// FolderPeek: hover over a Desktop folder and its files fan out around it.
// Polls the pointer at 30 Hz: cheap, needs no global event monitors, and one
// loop handles both the open dwell and the close grace period.

let dwellDelay: TimeInterval = 0.4
let closeDelay: TimeInterval = 0.3
let spaceKeyCode: Int64 = 49

final class AppDelegate: NSObject, NSApplicationDelegate, QLPreviewPanelDataSource {
  private let watcher = DesktopWatcher()
  private let ring = RingPanel()
  private var timer: Timer?
  private var permissionTimer: Timer?

  private var lastPoint = CGPoint(x: -1, y: -1)
  private var lastHit: (url: URL, iconFrame: CGRect)?
  private var candidate: (url: URL, since: Date)?
  private var outsideSince: Date?

  private var spaceTap: CFMachPort?
  private var previewURL: URL?

  func applicationDidFinishLaunching(_ note: Notification) {
    let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if AXIsProcessTrustedWithOptions(prompt) {
      start()
      return
    }
    // Not trusted yet, or a stale grant from an older build: send the user to
    // the right Settings pane and wait.
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
      if AXIsProcessTrusted() { t.invalidate(); self?.start() }
    }
  }

  private func start() {
    installSpaceTap()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
  }

  // MARK: Pointer loop

  private func tick() {
    let p = NSEvent.mouseLocation
    let now = Date()

    ring.updateHover(at: p)
    if ring.isOpen {
      if ring.contains(p) || ring.isDragging {
        outsideSince = nil
        return
      }
      if outsideSince == nil { outsideSince = now }
      if now.timeIntervalSince(outsideSince!) >= closeDelay {
        ring.close()
        outsideSince = nil
        candidate = nil
      }
    }

    // Never open while a button is down (moving icons, selecting, dragging).
    if NSEvent.pressedMouseButtons != 0 { candidate = nil; return }

    if p != lastPoint {
      lastPoint = p
      lastHit = watcher.folder(at: p)
    }
    guard let hit = lastHit else { candidate = nil; return }
    if ring.isOpen && ring.folder == hit.url { return }

    if candidate?.url != hit.url { candidate = (hit.url, now); return }
    if now.timeIntervalSince(candidate!.since) >= dwellDelay {
      candidate = nil
      if ring.isOpen { ring.close(animated: false) }
      ring.show(folder: hit.url, iconFrame: hit.iconFrame)
      outsideSince = nil
    }
  }

  // MARK: Space → Quick Look

  private func installSpaceTap() {
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let me = Unmanaged.passUnretained(self).toOpaque()
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: mask, callback: spaceTapCallback, userInfo: me) else {
      NSLog("FolderPeek: could not create the Space key tap")
      return
    }
    spaceTap = tap
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
  }

  fileprivate func reenableTap() {
    if let spaceTap { CGEvent.tapEnable(tap: spaceTap, enable: true) }
  }

  /// Returns true when the Space press was ours and must not reach Finder.
  fileprivate func handleSpace() -> Bool {
    let panel = QLPreviewPanel.shared()!
    if panel.isVisible && previewURL != nil && !ring.isOpen {
      panel.orderOut(nil)
      previewURL = nil
      return true
    }
    guard ring.isOpen, let entry = ring.hoveredEntry else { return false }
    if panel.isVisible && previewURL == entry.url {
      panel.orderOut(nil)
      previewURL = nil
      return true
    }
    previewURL = entry.url
    NSApp.activate()
    panel.dataSource = self
    panel.reloadData()
    panel.makeKeyAndOrderFront(nil)
    return true
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { previewURL as NSURL? }

  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self }
  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { previewURL = nil }
}

private func spaceTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
  guard let refcon else { return Unmanaged.passUnretained(event) }
  let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    delegate.reenableTap()
    return Unmanaged.passUnretained(event)
  }
  if type == .keyDown,
     event.getIntegerValueField(.keyboardEventKeycode) == spaceKeyCode,
     event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
     event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
     delegate.handleSpace() {
    return nil
  }
  return Unmanaged.passUnretained(event)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
