import CoreGraphics
import Foundation

// Pure geometry for the ring: where each item goes around a Desktop icon so
// that everything stays inside the screen's visible frame.
//
// Items sit on a honeycomb (hex) grid centered on the icon, filling the cells
// nearest the icon first. That keeps the files snug at any count, and against
// an edge or in a corner the off-screen cells simply drop out, so the cluster
// bends toward the middle of the screen on its own.

let minSpacing: CGFloat = 96   // distance between neighboring cells
let itemMargin: CGFloat = 44   // half an item; centers keep this far from the edges
let maxFiles = 9
let haloPadding: CGFloat = 58
let emptyHaloRadius: CGFloat = 98
private let maxRings = 5        // how far out the grid extends

struct RingSlot {
  let center: CGPoint
  let ring: Int                 // 0 = touching the icon, 1 = next row out, ...
}

struct RingLayout {
  let slots: [RingSlot]
  let haloRadius: CGFloat
  let fileCount: Int
  let showsMore: Bool
}

func computeRingLayout(center: CGPoint, bounds: CGRect, totalFiles: Int) -> RingLayout {
  guard totalFiles > 0 else {
    return RingLayout(slots: [], haloRadius: emptyHaloRadius, fileCount: 0, showsMore: false)
  }
  let safe = bounds.insetBy(dx: itemMargin, dy: itemMargin)
  let rowHeight = minSpacing * sqrt(3) / 2
  // Ties at the same distance go to the cell facing the middle of the screen.
  let toMiddle = CGVector(dx: bounds.midX - center.x, dy: bounds.midY - center.y)
  let len = max(hypot(toMiddle.dx, toMiddle.dy), 1)

  var cells: [(point: CGPoint, distance: CGFloat, facing: CGFloat)] = []
  for row in -maxRings...maxRings {
    let offset = row.isMultiple(of: 2) ? 0 : minSpacing / 2
    for col in -maxRings - 1...maxRings {
      let dx = CGFloat(col) * minSpacing + offset, dy = CGFloat(row) * rowHeight
      let d = hypot(dx, dy)
      guard d > 1, d <= CGFloat(maxRings) * minSpacing + 1 else { continue }
      let p = CGPoint(x: center.x + dx, y: center.y + dy)
      guard safe.contains(p) else { continue }
      cells.append((p, d, (dx * toMiddle.dx + dy * toMiddle.dy) / (d * len)))
    }
  }
  cells.sort { abs($0.distance - $1.distance) > 1 ? $0.distance < $1.distance : $0.facing > $1.facing }

  let needed = min(totalFiles, maxFiles) + (totalFiles > maxFiles ? 1 : 0)
  let chosen = cells.prefix(needed)
  let slots = chosen.map { RingSlot(center: $0.point, ring: Int(($0.distance / minSpacing).rounded(.down)) - 1) }

  let fits = slots.count >= needed
  let fileCount = fits ? min(totalFiles, maxFiles) : max(slots.count - 1, 0)
  let showsMore = fits ? totalFiles > maxFiles : !slots.isEmpty
  let haloRadius = (chosen.map(\.distance).max() ?? 0) + haloPadding
  return RingLayout(slots: slots, haloRadius: haloRadius, fileCount: fileCount, showsMore: showsMore)
}
