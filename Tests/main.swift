import CoreGraphics
import Foundation

var failures = 0
var checks = 0
func check(_ cond: Bool, _ msg: String) {
  checks += 1
  if !cond { failures += 1; print("FAIL:", msg) }
}

func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
func pairwiseOK(_ s: [RingSlot]) -> Bool {
  for i in s.indices { for j in s.indices where j > i { if dist(s[i].center, s[j].center) < minSpacing - 0.5 { return false } } }
  return true
}

// MARK: Layout

let screen = CGRect(x: 0, y: 0, width: 1470, height: 900)
let safe = screen.insetBy(dx: itemMargin, dy: itemMargin)

func maxDist(_ l: RingLayout, _ c: CGPoint) -> CGFloat { l.slots.map { dist($0.center, c) }.max() ?? 0 }
let snug = minSpacing * 2 + 1   // second row of the honeycomb

do { // openSpace5: one snug row around the icon
  let c = CGPoint(x: 700, y: 450)
  let l = computeRingLayout(center: c, bounds: screen, totalFiles: 5)
  check(l.slots.count == 5 && !l.showsMore, "openSpace5 count \(l.slots.count)")
  check(maxDist(l, c) <= minSpacing + 1, "openSpace5 all touching the icon")
  check(pairwiseOK(l.slots), "openSpace5 spacing")
}
do { // openSpace30
  let c = CGPoint(x: 700, y: 450)
  let l = computeRingLayout(center: c, bounds: screen, totalFiles: 30)
  check(l.slots.count == 10, "openSpace30 count \(l.slots.count)")
  check(l.fileCount == 9 && l.showsMore, "openSpace30 9 files + more")
  check(maxDist(l, c) <= snug, "openSpace30 snug")
  check(pairwiseOK(l.slots), "openSpace30 spacing")
}
do { // topRightCorner30
  let c = CGPoint(x: 1399, y: 850)
  let l = computeRingLayout(center: c, bounds: screen, totalFiles: 30)
  check(l.slots.allSatisfy { safe.contains($0.center) }, "corner inside bounds")
  let mx = l.slots.map(\.center.x).reduce(0,+) / CGFloat(l.slots.count), my = l.slots.map(\.center.y).reduce(0,+) / CGFloat(l.slots.count)
  check(mx < c.x - 60 && my < c.y - 60, "corner opens down-left")
  check(l.showsMore && l.fileCount + 1 == l.slots.count, "corner more bubble")
  check(l.slots.count == 10, "corner count \(l.slots.count)")
  check(pairwiseOK(l.slots), "corner spacing")
}
do { // topEdge9: OPT, all 9 files and no gap
  let c = CGPoint(x: 1173, y: 850)
  let l = computeRingLayout(center: c, bounds: screen, totalFiles: 9)
  check(l.slots.allSatisfy { safe.contains($0.center) }, "edge inside bounds")
  check(l.slots.allSatisfy { $0.center.y <= c.y + 8 }, "edge opens downward")
  check(l.fileCount == 9 && !l.showsMore, "edge all 9 files (got \(l.fileCount), \(l.showsMore))")
  check(maxDist(l, c) <= snug, "edge snug (\(maxDist(l, c)))")
  check(l.slots.filter { dist($0.center, c) <= minSpacing + 1 }.count >= 4, "edge first row hugs the icon")
  check(pairwiseOK(l.slots), "edge spacing")
}
do { // empty
  let l = computeRingLayout(center: CGPoint(x: 700, y: 450), bounds: screen, totalFiles: 0)
  check(l.slots.isEmpty && l.haloRadius == 98, "empty")
}

// MARK: Folder reading

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("folderpeek-tests-\(UUID().uuidString)")
try! fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }

func touch(_ url: URL, _ t: TimeInterval) {
  fm.createFile(atPath: url.path, contents: Data())
  try! fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: t)], ofItemAtPath: url.path)
}

do { // readsNewestFirst
  let d = root.appendingPathComponent("order"); try! fm.createDirectory(at: d, withIntermediateDirectories: true)
  touch(d.appendingPathComponent("a"), 1000); touch(d.appendingPathComponent("b"), 3000); touch(d.appendingPathComponent("c"), 2000)
  check(readFolder(d).map(\.name) == ["b", "c", "a"], "newest first \(readFolder(d).map(\.name))")
}
do { // skipsHidden
  let d = root.appendingPathComponent("hidden"); try! fm.createDirectory(at: d, withIntermediateDirectories: true)
  touch(d.appendingPathComponent(".hidden"), 1); touch(d.appendingPathComponent(".DS_Store"), 1); touch(d.appendingPathComponent("x.txt"), 1)
  check(readFolder(d).map(\.name) == ["x.txt"], "skips hidden")
}
do { // emptyFolder
  let d = root.appendingPathComponent("empty"); try! fm.createDirectory(at: d, withIntermediateDirectories: true)
  check(readFolder(d).isEmpty, "empty folder")
}
do { // resolvesFolder
  let desk = root.appendingPathComponent("desk"), other = root.appendingPathComponent("other")
  let folder = desk.appendingPathComponent("Folder")
  try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
  try! fm.createDirectory(at: desk.appendingPathComponent("Thing.app"), withIntermediateDirectories: true)
  try! fm.createDirectory(at: other.appendingPathComponent("Folder"), withIntermediateDirectories: true)
  touch(desk.appendingPathComponent("file.txt"), 1)
  try! fm.createSymbolicLink(at: desk.appendingPathComponent("link"), withDestinationURL: folder)
  let std = folder.resolvingSymlinksInPath().path
  check(resolveDesktopFolder(folder, desktop: desk)?.resolvingSymlinksInPath().path == std, "resolves folder")
  check(resolveDesktopFolder(desk.appendingPathComponent("file.txt"), desktop: desk) == nil, "file is not a folder")
  check(resolveDesktopFolder(desk.appendingPathComponent("Thing.app"), desktop: desk) == nil, "package is not a folder")
  check(resolveDesktopFolder(desk.appendingPathComponent("link"), desktop: desk)?.resolvingSymlinksInPath().path == std, "symlink resolves")
  check(resolveDesktopFolder(other.appendingPathComponent("Folder"), desktop: desk) == nil, "outside desktop")
}

if failures > 0 { print("\(failures) of \(checks) checks failed"); exit(1) }
print("all \(checks) checks passed")
