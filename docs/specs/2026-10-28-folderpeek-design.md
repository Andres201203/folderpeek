# FolderPeek: design

Date: 2026-10-28 · Owner: Andres · Status: draft, awaiting approval (builder-checked)

## Why

Andres keeps a few working folders on his Desktop (today: `Docs`, `Client Project`, `Temp`). Two everyday frictions:

1. **Grab.** He knows a file is in `Docs` and wants to drag it into a browser upload, a Mail message, or the Claude Code terminal (Ghostty). Today he has to open the folder in Finder first.
2. **Glance.** He wants to know what is in `Temp` without opening a Finder window.

Success: hover over a Desktop folder, see its files, then open or drag one out without opening Finder.

## Goals

- Hover over a folder icon on the Desktop. After a short pause, its files fan out around the icon in a frosted-glass **ring**.
- **Newest files first.** Up to 7 files sit on the ring. If there are more, the last slot becomes a `+N` bubble. Clicking it opens a scrollable grid of every file in the same glass style, anchored to the ring.
- **The ring adapts to the screen edges** (approved mockup `ring-corner.html`): a full ring in open space, a half ring against one edge, a quarter ring in a corner, always opening toward the middle of the screen. It never goes under the menu bar, under the Dock, or off-screen.
- The glass behind the ring blurs whatever sits under it, neighboring folders included. *(Claude's call: the mockup showed other icons fading, but Finder draws those icons and FolderPeek can't dim them without a full-screen overlay. The blur gives the same effect natively, so no separate fade.)*
- Actions on a file in the ring or grid:
  - **Click** opens it in its default app.
  - **Drag** hands off a real file (file URL on the pasteboard). Dropping works in Safari/Chrome uploads, Mail, Ghostty (which pastes the path), and Finder.
  - **Space** shows a Quick Look preview of the file under the pointer, like Finder. *(Claude's call.)* The panel never takes focus, so a key event tap catches Space only while the pointer is over a ring or grid item. At all other times Space goes to Finder as usual.
- Moving the mouse off the ring (and off the folder) folds it back into the folder.
- Visual style: Apple-native. **Liquid Glass** (`NSGlassEffectView`), the current macOS 26 material used by Control Center *(Claude's call)*, real system file icons/thumbnails (QuickLook thumbnails for images and PDFs), SF font, spring animation on open and close. The approved mockups are the reference: `ring-polish.html` (2: messy folder) and `ring-corner.html`.
- **Fully local.** No network, no telemetry, no accounts.

## Non-goals

- Folders anywhere other than the Desktop (Finder windows, the Dock, etc.).
- Browsing into subfolders. Andres rarely nests folders on the Desktop. A subfolder appears as an item and clicking it opens it in Finder. *(Claude's call.)*
- Hovering over files (only folders trigger the ring).
- Renaming, deleting, or tagging files from the ring.
- Settings UI. Defaults are hard-coded; change them in code.

## Anti-goals (a failure even if it "works")

- Popping up while he's just moving the mouse across the Desktop, i.e. too eager.
- Anything that looks like a web view or a non-native panel.
- Slowing down the Mac or Finder (e.g. polling the file system constantly).
- Any file content leaving the machine.

## Constraints

- **macOS 26 (Tahoe) only**, Apple Silicon, Swift 6.2 toolchain (`-target arm64-apple-macos26.0`). No Xcode project. *(Claude's call.)*
- Same packaging as `~/ClaudeMeter`: `swiftc` plus a `build.sh` that assembles the `.app`, ad-hoc signs it, and offers `--install`/`--uninstall` for a LaunchAgent so it starts at login. `LSUIElement` (no Dock icon).
- Needs the **Accessibility** permission, granted once in System Settings. The app should detect a missing permission and open the right Settings pane.
- **Stable signing identity:** ad-hoc signing changes the signature on every build, and macOS then silently drops the Accessibility grant. So `build.sh` creates a local self-signed code-signing certificate once (in the login keychain, named e.g. `FolderPeek Local`) and signs every build with it. The first-run check must also handle a grant that is listed but stale (`AXIsProcessTrusted()` returns false): show how to remove and re-add the app. *(Claude's call.)*

## How (decided)

- **Native Swift/AppKit app** running in the background. Lives in `~/FolderPeek`. *(Claude's call, modeled on Claude Meter.)*
- **Finding the hovered icon:** use the Accessibility API on Finder. Global mouse-moved monitor → `AXUIElementCopyElementAtPosition` on Finder's process → if the element is a Desktop icon (not an item in a Finder window), read its name and frame. Resolve the name to `~/Desktop/<name>`. What counts as a folder *(Claude's call)*: real directories trigger the ring; aliases and symlinks to folders are followed and also trigger it; packages and bundles (`.app`, `.key`, `.photoslibrary`, etc.) do not. If the Desktop syncs with iCloud, files that aren't downloaded show with a small cloud badge and are never downloaded just to build the ring.
- **Showing the ring:** a borderless, non-activating, transparent `NSPanel` above the Desktop, using `NSVisualEffectView` for the glass. Item positions come from the icon's center, the screen's `visibleFrame` (which excludes the menu bar and Dock), and the edge rules above.
- **File listing:** read the folder's contents when the ring opens. Skip hidden files and `.DS_Store`. Sort by date modified, newest first.

## Left to the builder

- Exact hover delay (suggest ~0.4 s) and close grace period. Tune them so the anti-goal "too eager" doesn't happen.
- Ring radii, the two-arc layout for the half and quarter cases, and animation curves. Match the mockups.
- What happens when a drop lands in another Finder folder: follow Finder's default (move on the same disk, copy across disks, Option forces a copy). *(Claude's call.)*
- Multiple displays: works on whichever screen holds the Desktop icons.
- Edge cases: a Desktop covered by windows (the ring only opens when the icon is actually under the mouse, which AX handles), file-name truncation, folder contents changing while the ring is open, an empty folder (show a small "Empty" ring).
