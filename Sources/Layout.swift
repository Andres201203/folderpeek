import CoreGraphics
import Foundation

// Pure geometry for the ring: where each item goes around a Desktop icon so
// that everything stays inside the screen's visible frame.

let innerRadius: CGFloat = 118
let outerRadius: CGFloat = 214
let minSpacing: CGFloat = 92   // straight-line distance between neighboring item centers
let itemMargin: CGFloat = 44   // half an item; centers keep this far from the edges
let maxFiles = 7
let haloPadding: CGFloat = 58
let maxSingleRadius: CGFloat = 210  // grow one arc up to this before using a second ring

struct RingSlot {
  let center: CGPoint
  let ring: Int
}

struct RingLayout {
  let slots: [RingSlot]
  let haloRadius: CGFloat
  let fileCount: Int
  let showsMore: Bool
}

/// Largest contiguous run of allowed whole-degree angles, as (start, length in
/// degrees), or nil if no angle fits. A full circle returns length 360.
private func largestArc(center: CGPoint, radius: CGFloat, safe: CGRect) -> (start: Int, length: Int)? {
  let allowed = (0..<360).map { deg -> Bool in
    let a = CGFloat(deg) * .pi / 180
    return safe.contains(CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
  }
  if allowed.allSatisfy({ $0 }) { return (0, 360) }
  guard let firstBlocked = allowed.firstIndex(of: false) else { return nil }
  var best: (Int, Int)? = nil
  var runStart = -1, runLen = 0
  // Walk once around starting just after a blocked angle so runs never wrap.
  for step in 1...360 {
    let deg = (firstBlocked + step) % 360
    if allowed[deg] {
      if runLen == 0 { runStart = deg }
      runLen += 1
      if runLen > (best?.1 ?? 0) { best = (runStart, runLen) }
    } else {
      runLen = 0
    }
  }
  return best
}

private struct Ring {
  let radius: CGFloat
  let arc: (start: Int, length: Int)?

  /// Smallest angle (degrees) between two items on this ring.
  var minStepDeg: CGFloat { 2 * asin(minSpacing / (2 * radius)) * 180 / .pi }

  var capacity: Int {
    guard let arc else { return 0 }
    if arc.length == 360 { return Int(360 / minStepDeg) }
    return Int(CGFloat(arc.length - 1) / minStepDeg) + 1
  }

  func points(_ count: Int, center: CGPoint) -> [CGPoint] {
    guard let arc, count > 0 else { return [] }
    let point = { (deg: CGFloat) -> CGPoint in
      let a = deg * .pi / 180
      return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    }
    if arc.length == 360 {
      return (0..<count).map { point(90 - CGFloat($0) * 360 / CGFloat(count)) }
    }
    let mid = CGFloat(arc.start) + CGFloat(arc.length - 1) / 2
    if count == 1 { return [point(mid)] }
    // Spread evenly, but no wider than 1.4x the minimum so few items stay grouped.
    let span = CGFloat(arc.length - 1)
    let step = min(span / CGFloat(count - 1), minStepDeg * 1.4)
    let first = mid - step * CGFloat(count - 1) / 2
    return (0..<count).map { point(first + CGFloat($0) * step) }
  }
}

func computeRingLayout(center: CGPoint, bounds: CGRect, totalFiles: Int) -> RingLayout {
  guard totalFiles > 0 else {
    return RingLayout(slots: [], haloRadius: innerRadius - 20, fileCount: 0, showsMore: false)
  }
  let safe = bounds.insetBy(dx: itemMargin, dy: itemMargin)
  let needed = min(totalFiles, maxFiles) + (totalFiles > maxFiles ? 1 : 0)

  // One clean arc reads best: widen it until every slot fits.
  for r in stride(from: innerRadius, through: maxSingleRadius, by: 4) {
    let ring = Ring(radius: r, arc: largestArc(center: center, radius: r, safe: safe))
    if ring.capacity >= needed {
      let slots = ring.points(needed, center: center).map { RingSlot(center: $0, ring: 0) }
      return RingLayout(slots: slots, haloRadius: r + haloPadding,
                        fileCount: min(totalFiles, maxFiles), showsMore: totalFiles > maxFiles)
    }
  }

  // Tight spots (corners): two rings.
  let inner = Ring(radius: innerRadius, arc: largestArc(center: center, radius: innerRadius, safe: safe))
  let outer = Ring(radius: outerRadius, arc: largestArc(center: center, radius: outerRadius, safe: safe))

  let onInner = min(needed, inner.capacity)
  let onOuter = min(needed - onInner, outer.capacity)
  let slotCount = onInner + onOuter

  let slots = inner.points(onInner, center: center).map { RingSlot(center: $0, ring: 0) }
    + outer.points(onOuter, center: center).map { RingSlot(center: $0, ring: 1) }

  let fits = slotCount >= needed
  let fileCount = fits ? min(totalFiles, maxFiles) : max(slotCount - 1, 0)
  let showsMore = fits ? totalFiles > maxFiles : slotCount > 0
  let haloRadius = (onOuter > 0 ? outerRadius : innerRadius) + haloPadding
  return RingLayout(slots: slots, haloRadius: haloRadius, fileCount: fileCount, showsMore: showsMore)
}
