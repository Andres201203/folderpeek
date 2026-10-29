# FolderPeek Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A background Mac app: hover over a Desktop folder and its files fan out in a Liquid Glass ring that bends to fit the screen edges. Click opens a file, drag hands it off, Space previews it.

**Architecture:** One `swiftc`-built AppKit agent app (`LSUIElement`). A global mouse monitor hit-tests Finder through the Accessibility API to find the Desktop icon under the pointer. A pure `RingLayout` computes item slots from the icon center and the screen's `visibleFrame`. A transparent non-activating `NSPanel` hosts an `NSGlassEffectView` disc plus file item views. Pure logic (layout, folder reading, folder resolution) is unit-tested with a plain `swiftc` test runner. UI is verified by running the app.

**Tech Stack:** Swift 6.2 (`-swift-version 5` language mode for AppKit ergonomics), AppKit, ApplicationServices (AX), QuickLookThumbnailing, Quartz (QLPreviewPanel), CoreGraphics event tap.

**Spec:** `docs/specs/2026-10-28-folderpeek-design.md`

## Global Constraints

- Target `arm64-apple-macos26.0`; macOS 26 only.
- Fully local: no networking APIs anywhere.
- `LSUIElement` true, bundle id `com.andres.folderpeek`, app `FolderPeek.app`, executable `FolderPeek`.
- Signed with a stable local identity `FolderPeek Local` (created once by `build.sh`), never ad-hoc.
- Max 9 files on the ring (was 7; changed after UAT). With more, the last slot is a `+N` bubble (N = total − files shown).
- Newest first, by `contentModificationDate`. Skip hidden files and `.DS_Store`.
- The ring never extends outside `NSScreen.visibleFrame` (no menu bar, no Dock, no off-screen).
- Only `~/Desktop` items trigger the ring. Directories and aliases/symlinks to directories trigger it; packages do not.

## Review Focus

1. Pointer sweeping across several icons quickly → no ring opens (dwell timer resets on every icon change).
2. Folder in a screen corner or against the menu bar → every slot center plus a 44 pt half-item margin lies inside `visibleFrame` (tested in Task 1).
3. Drag a file into Finder on the same disk (move) → the ring refreshes or closes and doesn't show a stale item.
4. Folder with 0 files, or with only hidden files → "Empty" disc, no crash (tested in Task 2).
5. A Finder window covering a Desktop folder → hovering the window does not open the ring (AX hit-test returns the window; tested manually in Task 4).

---

### Task 1: Pure ring layout

**Files:**
- Create: `Sources/Layout.swift`
- Create: `Tests/main.swift` (test runner: `check(_ cond: Bool, _ msg: String)` counting failures, `exit(1)` if any)
- Create: `test.sh` (`swiftc Sources/Layout.swift Sources/FolderReader.swift Tests/main.swift -o .build/tests && .build/tests`)

**Interfaces:**
- Produces:
  - `struct RingSlot { let center: CGPoint; let ring: Int }` (ring 0 = inner, 1 = outer)
  - `struct RingLayout { let slots: [RingSlot]; let haloRadius: CGFloat; let fileCount: Int; let showsMore: Bool }`
  - `func computeRingLayout(center: CGPoint, bounds: CGRect, totalFiles: Int) -> RingLayout`
  - Constants: `innerRadius = 118`, `outerRadius = 214` (≥ minSpacing beyond inner so rings never collide), `minSpacing: CGFloat = 92` (arc length between centers), `itemMargin: CGFloat = 44`, `maxFiles = 7`, `haloPadding = 58`.

Algorithm (spelled out because the tests don't determine it): for each radius, sample angles at 1° steps and mark an angle allowed when `center + r·(cos, sin)` inset by `itemMargin` lies inside `bounds`. Take the largest contiguous allowed run (wrapping around 360°). If every angle is allowed, the capacity is `floor(2πr / minSpacing)` evenly spaced, starting at 90° (top). Otherwise the capacity is `floor(arcLen / minSpacing) + 1`, spread evenly across the run, or one slot at the run's midpoint if the run is shorter than `minSpacing`. Fill the inner ring first. Use the outer ring only when the inner one can't hold the needed slots. Needed slots: `min(total, 7) + (total > 7 ? 1 : 0)`. If total capacity < needed and total > capacity, show `capacity − 1` files plus a more bubble. `haloRadius` = the outermost used radius + `haloPadding`, or `innerRadius - 20` when total = 0.

- [ ] **Step 1: Write failing tests** in `Tests/main.swift`:
  - `openSpace5`: center (700,450), bounds (0,0,1470,900), total 5 → 5 slots, all ring 0, `showsMore == false`, pairwise distance ≥ 92.
  - `openSpace30`: same, total 30 → 8 slots, `fileCount == 7`, `showsMore == true`.
  - `topRightCorner30`: center (1399,850), bounds (0,0,1470,900) (the menu bar is already excluded), total 30 → every slot is inside `bounds.insetBy(44,44)`; the mean slot is > 60 pt left of and below the center; `showsMore`; `fileCount + 1 == slots.count`; `slots.count >= 6`.
  - `topEdge8`: center (735,850), total 8 → all inside the inset bounds; all y ≤ center.y+8; `fileCount == 7`, `showsMore`.
  - `empty`: total 0 → 0 slots, `haloRadius == 98`.
- [ ] **Step 2:** `./test.sh` → fails to compile (no `computeRingLayout`).
- [ ] **Step 3:** Implement `computeRingLayout` in `Sources/Layout.swift`.
- [ ] **Step 4:** `./test.sh` → `all N checks passed`.
- [ ] **Step 5:** Commit `feat: ring layout that bends to screen edges`.

### Task 2: Folder reading and Desktop folder resolution

**Files:**
- Create: `Sources/FolderReader.swift`
- Modify: `Tests/main.swift`

**Interfaces:**
- Produces:
  - `struct FileEntry { let url: URL; let name: String; let modified: Date; let isDirectory: Bool; let isCloudPlaceholder: Bool }`
  - `func readFolder(_ url: URL) -> [FileEntry]`: newest first; skips hidden files and `.DS_Store`; `isCloudPlaceholder` is true when `ubiquitousItemDownloadingStatus` is set and ≠ `.current`.
  - `func resolveDesktopFolder(_ url: URL, desktop: URL) -> URL?`: returns the resolved directory URL when `url`'s parent is `desktop` (standardized) and it is a directory (non-package), or an alias/symlink to one. Otherwise nil.

- [ ] **Step 1: Write failing tests** using a temp dir under `FileManager.default.temporaryDirectory/folderpeek-tests-<uuid>`:
  - `readsNewestFirst`: files a, b, c with modification dates 1, 3, 2 → names `[b, c, a]`.
  - `skipsHidden`: `.hidden` and `.DS_Store` plus `x.txt` → `[x.txt]`.
  - `emptyFolder`: an empty dir → `[]`.
  - `resolvesFolder`: `desk/Folder` → its URL; `desk/file.txt` → nil; `desk/Thing.app` (a dir) → nil; `desk/link` symlink → `desk/Folder` → resolves to `desk/Folder`; `other/Folder` with desktop `desk` → nil.
- [ ] **Step 2:** `./test.sh` → fails.
- [ ] **Step 3:** Implement both functions (`contentsOfDirectory(at:includingPropertiesForKeys:options: .skipsHiddenFiles)`, `resourceValues` for `isDirectory`/`isPackage`/`isAliasFile`/`isSymbolicLink`, `URL(resolvingAliasFileAt:)`).
- [ ] **Step 4:** `./test.sh` → all pass.
- [ ] **Step 5:** Commit `feat: read and resolve Desktop folders`.

### Task 3: Build script with stable signing

**Files:**
- Create: `build.sh` (modeled on `~/ClaudeMeter/build.sh`: `--install` / `--uninstall` LaunchAgent label `com.andres.folderpeek`)
- Create: `.gitignore` (`.build/`, `FolderPeek.app/`)

- [ ] **Step 1:** In `build.sh`, before signing: if `security find-certificate -c "FolderPeek Local"` fails, create a self-signed code-signing cert with `openssl` (`extendedKeyUsage=codeSigning`, 10 years) and import it as a `.p12` into the login keychain with `-T /usr/bin/codesign`. Then `codesign --force --sign "FolderPeek Local" --identifier com.andres.folderpeek`.
- [ ] **Step 2:** Run `./test.sh` first inside `build.sh`; abort the build on failure.
- [ ] **Step 3:** With a stub `Sources/main.swift` that just runs `NSApplication`, run `./build.sh` twice → `codesign -dr - FolderPeek.app` prints the same designated requirement both times (it contains `certificate leaf = H"…"`, not `cdhash`).
- [ ] **Step 4:** Commit `build: app bundle with stable local signing identity`.

### Task 4: Hover detection

**Files:**
- Create: `Sources/DesktopWatcher.swift`
- Modify: `Sources/main.swift` (AppDelegate: permission check → `AXIsProcessTrustedWithOptions` with prompt; if not trusted, open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`, poll every 2 s until trusted, then start the watcher)

**Interfaces:**
- Consumes: `resolveDesktopFolder` (Task 2).
- Produces: `final class DesktopWatcher { var onHover: (URL, CGRect) -> Void; var onLeave: () -> Void; func start() }`. The `CGRect` is the icon frame in AppKit screen coordinates (flipped from AX top-left coordinates using the primary screen height).

Behavior: a global `.mouseMoved` monitor runs `AXUIElementCopyElementAtPosition(systemWide, …)`. It accepts only when the pid is Finder, role is `AXImage`, the element has no `AXWindow` ancestor (walk `AXParent`), and `AXURL` → `NSURL.filePathURL` resolves through `resolveDesktopFolder`. The dwell is **0.4 s** on the same path, and it resets when the path changes. Never trigger while any mouse button is down (`NSEvent.pressedMouseButtons != 0`).

- [ ] **Step 1:** Implement, with a temporary `NSLog("hover \(path)")` in `onHover`.
- [ ] **Step 2:** `./build.sh && open FolderPeek.app`. Hover Docs for ~0.5 s, then sweep across all three folders quickly. Verify in `log stream --predicate 'process == "FolderPeek"'`: one `hover …/Docs` for the dwell and none for the fast sweep. Hover a Finder window placed over a folder → no log.
- [ ] **Step 3:** Commit `feat: detect dwell on Desktop folders via Accessibility`.

### Task 5: The ring panel

**Files:**
- Create: `Sources/RingPanel.swift`
- Modify: `Sources/main.swift` (wire `onHover` → `RingPanel.show(folder:iconFrame:)`)

**Interfaces:**
- Consumes: `computeRingLayout`, `readFolder`, `DesktopWatcher`.
- Produces: `final class RingPanel { func show(folder: URL, iconFrame: CGRect); func close(); var isOpen: Bool; func contains(screenPoint: CGPoint) -> Bool }`

Details:
- `NSPanel` with `[.borderless, .nonactivatingPanel]`, `level = .floating`, clear background, `hasShadow = false`, `collectionBehavior = [.canJoinAllSpaces, .transient]`. Frame = the halo's bounding square ∩ `screen.visibleFrame`. Clicks on transparent pixels fall through.
- The halo is a circular `NSGlassEffectView` (`cornerRadius = haloRadius`) placed so its center is the icon center (it may extend past the panel bounds and gets clipped).
- `FileItemView` per slot: 84 pt wide, a 48 pt icon (`NSWorkspace.icon(forFile:)`, upgraded to a `QLThumbnailGenerator` thumbnail for images and PDFs), and a two-line truncated name with a text shadow. Hover: scale 1.15 and blue name pill. Cloud placeholder: an `icloud` SF Symbol badge, and no thumbnail request.
- `+N` bubble: a 44 pt glass circle labeled `+N` with "See all" below. Empty folder: an "Empty" label in the halo.
- Open animation: items spring out from the icon center (staggered 0.02 s, ~0.35 s); close reverses. Both use `NSAnimationContext` with `allowsImplicitAnimation`.
- Close rule: in main.swift, a global plus local mouseMoved check closes the ring after **0.3 s** with the pointer outside both the halo circle and the icon frame. Never while a drag session is active.

- [ ] **Step 1:** Implement, and remove the hover NSLog.
- [ ] **Step 2:** Build and run. Hover each of Docs, Client Project, and Temp. Take a screenshot (`screencapture -x`). Check that the ring bends in the corner, nothing sits under the menu bar or off-screen, and files are newest first (compare with `ls -t ~/Desktop/Docs`).
- [ ] **Step 3:** Commit `feat: Liquid Glass ring of folder contents`.

### Task 6: Actions (click, drag, Space, see all)

**Files:**
- Modify: `Sources/RingPanel.swift`
- Create: `Sources/GridPanel.swift`

**Interfaces:**
- Produces: `final class GridPanel { func show(entries: [FileEntry], near: CGRect, on: NSScreen) }`: a glass rounded rect (radius 22), 4 columns of `FileItemView`, scrollable, max height 60% of `visibleFrame`, positioned toward the screen center from the icon and clamped inside `visibleFrame`. The ring stays open while the pointer is inside the grid.

Behavior:
- `FileItemView.acceptsFirstMouse` true. Click (mouse-up with no drag) → `NSWorkspace.shared.open(url)`, then close.
- Drag (mouse moves > 3 pt while down) → `beginDraggingSession` with `NSDraggingItem(pasteboardWriter: url as NSURL)` and the icon image. `sourceOperationMaskFor` outside the app → `[.copy, .move, .generic]`. On `endedAt` with `.move`, re-read the folder and re-layout (or close if the folder is now empty of the dragged file).
- Space: a `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: keyDown)`, enabled only while the ring is open. When keycode 49 arrives and the pointer is over a `FileItemView`, swallow it and toggle `QLPreviewPanel` for that URL (activate the app first, since QLPreviewPanel needs it). Otherwise pass the event through. Re-enable the tap on `tapDisabledByTimeout`.
- `+N` click → `GridPanel.show` with all entries.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Manual checks:
  - (a) Click a PDF in Docs → it opens in Preview.
  - (b) Drag a file onto the Ghostty prompt → its path appears.
  - (c) Drag into a Safari file upload or Mail → it attaches.
  - (d) Space over a file → Quick Look; Space over empty Desktop → Finder's own behavior.
  - (e) `+N` → a grid with all files.
  - (f) Copy 10 dummy files into a scratch Desktop folder to test `+N`, then delete that folder (only the one created for the test).
- [ ] **Step 3:** Commit `feat: open, drag, Quick Look and see-all grid`.

### Task 7: Install and final review

- [ ] **Step 1:** `./build.sh --install` → it runs at login. Grant Accessibility once.
- [ ] **Step 2:** Rebuild once more and confirm the permission persists (the ring still works without re-granting).
- [ ] **Step 3:** One fresh reviewer reviews the whole repo against the spec.
- [ ] **Step 4:** README with usage, and commit.
