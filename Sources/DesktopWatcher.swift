import AppKit
import ApplicationServices

// Finds the Desktop folder icon under a screen point by asking Finder through
// the Accessibility API. Windows covering the Desktop win the hit-test, so a
// folder hidden behind a window is never reported.

final class DesktopWatcher {
  private let system: AXUIElement = {
    // A hung app under the pointer must not stall us (default timeout is ~6 s).
    let e = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(e, 0.15)
    return e
  }()
  private let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

  /// `point` and the returned icon frame are in AppKit screen coordinates.
  func folder(at point: CGPoint) -> (url: URL, iconFrame: CGRect)? {
    let h = primaryScreenHeight
    // Finder answers AX hit-tests for Desktop icons even when a full-screen
    // app owns the screen, so first make sure the Desktop is what you see.
    guard desktopIsVisible(at: point) else { return nil }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(h - point.y), &hit) == .success,
          let el = hit else { return nil }

    var pid: pid_t = 0
    AXUIElementGetPid(el, &pid)
    guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder",
          string(el, kAXRoleAttribute) == kAXImageRole,
          !hasWindowAncestor(el),
          let ref = value(el, "AXURL") as? NSURL, let url = ref.filePathURL,
          let folder = resolveDesktopFolder(url, desktop: desktop),
          let frame = axFrame(el) else { return nil }

    // AX frames use a top-left origin on the primary screen.
    return (folder, CGRect(x: frame.minX, y: h - frame.maxY, width: frame.width, height: frame.height))
  }

  /// Whether the Desktop itself is what's showing at `point` (AppKit screen
  /// coordinates) on the current Space: Finder's Desktop window is on screen
  /// there and no app window covers it.
  func desktopIsVisible(at point: CGPoint) -> Bool {
    let p = CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    let me = ProcessInfo.processInfo.processIdentifier
    let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
    let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
    for w in windows {  // front to back
      guard let dict = w[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: dict), bounds.contains(p),
            let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
            (w[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
      let layer = w[kCGWindowLayer as String] as? Int ?? 0
      if layer == desktopLevel { return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder" }
      if layer >= 0 && layer < dockLevel { return false }
    }
    return false
  }

  private var primaryScreenHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

  private func hasWindowAncestor(_ el: AXUIElement) -> Bool {
    var current = el
    for _ in 0..<10 {
      guard let parent = value(current, kAXParentAttribute) else { return false }
      let p = parent as! AXUIElement
      if string(p, kAXRoleAttribute) == kAXWindowRole { return true }
      current = p
    }
    return false
  }

  private func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let pos = value(el, kAXPositionAttribute), let size = value(el, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
  }

  private func value(_ el: AXUIElement, _ attr: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
  }

  private func string(_ el: AXUIElement, _ attr: String) -> String? { value(el, attr) as? String }
}
