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
  fileprivate var swallowingSpace = false
  private let focusProbe: AXUIElement = {
    let e = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(e, 0.1)
    return e
  }()

  func applicationDidFinishLaunching(_ note: Notification) {
    let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if AXIsProcessTrustedWithOptions(prompt) {
      start()
      return
    }
    // Not trusted yet (the system prompt above offers to open Settings), or a
    // stale grant from an older build: wait until it's granted.
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
      if AXIsProcessTrusted() { t.invalidate(); self?.start() }
    }
  }

  private func start() {
    installSpaceTap()
    // Switching apps (click, Cmd-Tab) or desktops means you've moved on: close.
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.dismiss() }
    }
    // A preview left open while you switch away would keep catching Space.
    NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self, self.previewURL != nil else { return }
      QLPreviewPanel.shared()?.orderOut(nil)
      self.previewURL = nil
    }
    center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.dismiss()
    }
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
  }

  private func dismiss() {
    candidate = nil
    outsideSince = nil
    if ring.isOpen && !ring.isDragging { ring.close(animated: false) }
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
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
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
    // Our preview is in front: Space closes it, like Finder.
    if panel.isVisible && previewURL != nil && NSApp.isActive && panel.isKeyWindow {
      panel.orderOut(nil)
      previewURL = nil
      return true
    }
    guard ring.isOpen, let entry = ring.hoveredEntry, !isTyping() else { return false }
    previewURL = entry.url
    NSApp.activate()
    panel.dataSource = self
    panel.reloadData()
    panel.makeKeyAndOrderFront(nil)
    return true
  }

  /// Whether the keyboard focus is a text field or terminal, where Space must
  /// always type a space.
  private func isTyping() -> Bool {
    var focused: AnyObject?
    guard AXUIElementCopyAttributeValue(focusProbe, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let el = focused else { return false }
    var role: AnyObject?
    AXUIElementCopyAttributeValue(el as! AXUIElement, kAXRoleAttribute as CFString, &role)
    let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField", "AXWebArea"]
    return textRoles.contains(role as? String ?? "")
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
  guard event.getIntegerValueField(.keyboardEventKeycode) == spaceKeyCode else { return Unmanaged.passUnretained(event) }
  // Once a press is ours, its repeats and its key-up are ours too, so Finder
  // never sees half of it.
  if delegate.swallowingSpace {
    if type == .keyUp { delegate.swallowingSpace = false }
    return nil
  }
  if type == .keyDown,
     event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
     event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
     delegate.handleSpace() {
    delegate.swallowingSpace = true
    return nil
  }
  return Unmanaged.passUnretained(event)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
