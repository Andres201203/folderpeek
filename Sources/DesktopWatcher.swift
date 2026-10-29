import AppKit
import ApplicationServices

// Finds the Desktop folder icon under a screen point by asking Finder through
// the Accessibility API. Windows covering the Desktop win the hit-test, so a
// folder hidden behind a window is never reported.

final class DesktopWatcher {
  private let system = AXUIElementCreateSystemWide()
  private let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

  /// `point` and the returned icon frame are in AppKit screen coordinates.
  func folder(at point: CGPoint) -> (url: URL, iconFrame: CGRect)? {
    let h = primaryScreenHeight
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
