import AppKit

/// Library state. Plain observable-by-callback model (no SwiftUI, so the build
/// works with Command Line Tools alone).
final class LibraryModel {

    private(set) var packs: [Pack] = []

    /// Search/filter state. Setting it notifies the window so both the grid and
    /// the count update together.
    var query = LibraryQuery() {
        didSet {
            guard oldValue != query else { return }
            onChange?()
        }
    }

    var visiblePacks: [Pack] { query.apply(to: packs) }

    private let library: PackLibrary

    var onChange: (() -> Void)?
    var onApply: ((Pack) -> Void)?

    init(library: PackLibrary = PackLibrary()) {
        self.library = library
        reload()
    }

    func reload() {
        packs = library.scan()
        onChange?()
    }

    func add(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            let hasInfo = FileManager.default.fileExists(
                atPath: url.appendingPathComponent(PackFormat.infoFile).path
            )
            if hasInfo {
                library.addEntry(url)
            } else {
                library.addRoot(url)
            }
        } else {
            library.addEntry(url)
        }
        reload()
    }

    func revealLibraryFolder() {
        try? FileManager.default.createDirectory(
            at: PackLibrary.defaultRoot,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([PackLibrary.defaultRoot])
    }
}
