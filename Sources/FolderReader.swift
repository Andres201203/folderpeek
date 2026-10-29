import Foundation

// Reads a Desktop folder's files and decides which Desktop items count as folders.

struct FileEntry {
  let url: URL
  let name: String
  let modified: Date
  let isDirectory: Bool
  let isCloudPlaceholder: Bool
}

private let entryKeys: [URLResourceKey] = [
  .contentModificationDateKey, .isDirectoryKey, .isPackageKey, .ubiquitousItemDownloadingStatusKey,
]

/// Visible items in `url`, newest first.
func readFolder(_ url: URL) -> [FileEntry] {
  let urls = (try? FileManager.default.contentsOfDirectory(
    at: url, includingPropertiesForKeys: entryKeys, options: [.skipsHiddenFiles])) ?? []
  return urls
    .filter { $0.lastPathComponent != ".DS_Store" }
    .map { u in
      let v = try? u.resourceValues(forKeys: Set(entryKeys))
      let status = v?.ubiquitousItemDownloadingStatus
      return FileEntry(
        url: u,
        name: u.lastPathComponent,
        modified: v?.contentModificationDate ?? .distantPast,
        isDirectory: (v?.isDirectory ?? false) && !(v?.isPackage ?? false),
        isCloudPlaceholder: status != nil && status != .current)
    }
    .sorted { $0.modified > $1.modified }
}

/// The folder to show for a Desktop item, or nil if the item isn't directly on
/// `desktop` or isn't a plain folder (aliases and symlinks to folders count;
/// packages like .app do not).
func resolveDesktopFolder(_ url: URL, desktop: URL) -> URL? {
  let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
  guard parent.path == desktop.standardizedFileURL.resolvingSymlinksInPath().path else { return nil }

  var target = url
  if let v = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey]),
     v.isAliasFile == true || v.isSymbolicLink == true {
    guard let resolved = try? URL(resolvingAliasFileAt: url) else { return nil }
    target = resolved
  }
  guard let v = try? target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
        v.isDirectory == true, v.isPackage != true else { return nil }
  return target
}
