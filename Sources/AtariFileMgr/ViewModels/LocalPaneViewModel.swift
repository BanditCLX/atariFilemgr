// LocalPaneViewModel.swift — AtariFileMgr
// ViewModel for the left pane: browsing the local macOS filesystem.

import Foundation
import SwiftUI

@MainActor
final class LocalPaneViewModel: ObservableObject {

    // MARK: - Published state

    @Published var currentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var items: [LocalItem] = []
    @Published var selectedItems: Set<LocalItem> = []
    @Published var sortColumn: SortColumn = .name
    @Published var sortAscending: Bool = true
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Navigation history

    private var history: [URL] = []
    private var historyIndex: Int = -1

    var canGoBack:    Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    // MARK: - Sort

    enum SortColumn { case name, size, date, kind }

    // MARK: - Init

    init() {
        navigateTo(FileManager.default.homeDirectoryForCurrentUser, addToHistory: true)
    }

    // MARK: - Navigation

    func navigateTo(_ url: URL, addToHistory: Bool = true) {
        currentURL = url
        if addToHistory {
            // Trim forward history
            if historyIndex < history.count - 1 {
                history = Array(history.prefix(historyIndex + 1))
            }
            history.append(url)
            historyIndex = history.count - 1
        }
        refresh()
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        navigateTo(history[historyIndex], addToHistory: false)
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        navigateTo(history[historyIndex], addToHistory: false)
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent != currentURL else { return }
        navigateTo(parent)
    }

    // MARK: - Refresh

    func refresh() {
        isLoading = true
        Task {
            do {
                let fm = FileManager.default
                let contents = try fm.contentsOfDirectory(
                    at: currentURL,
                    includingPropertiesForKeys: [
                        .nameKey, .fileSizeKey, .contentModificationDateKey,
                        .isDirectoryKey, .isHiddenKey, .typeIdentifierKey
                    ],
                    options: [.skipsHiddenFiles]
                )
                var loaded = try contents.map { url -> LocalItem in
                    let resources = try url.resourceValues(forKeys: [
                        .nameKey, .fileSizeKey, .contentModificationDateKey,
                        .isDirectoryKey
                    ])
                    return LocalItem(
                        url:          url,
                        name:         resources.name ?? url.lastPathComponent,
                        isDirectory:  resources.isDirectory ?? false,
                        fileSize:     Int64(resources.fileSize ?? 0),
                        modifiedDate: resources.contentModificationDate ?? Date()
                    )
                }
                loaded = sort(loaded)
                self.items = loaded
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.items = []
                self.isLoading = false
            }
        }
    }

    // MARK: - Sorting

    func sort(_ items: [LocalItem]) -> [LocalItem] {
        items.sorted { a, b in
            // Directories always first
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let result: Bool
            switch sortColumn {
            case .name: result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .size: result = a.fileSize < b.fileSize
            case .date: result = a.modifiedDate < b.modifiedDate
            case .kind: result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
    }

    func setSort(_ column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
        items = sort(items)
    }

    // MARK: - Sidebar volumes

    var sidebarVolumes: [LocalItem] {
        let fm = FileManager.default
        return (fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? [])
            .map { url in
                LocalItem(url: url, name: url.lastPathComponent, isDirectory: true,
                          fileSize: 0, modifiedDate: Date())
            }
    }

    // MARK: - Favourite locations

    var favourites: [(name: String, url: URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("Home",      home),
            ("Desktop",   home.appendingPathComponent("Desktop")),
            ("Documents", home.appendingPathComponent("Documents")),
            ("Downloads", home.appendingPathComponent("Downloads")),
        ]
    }
}

// MARK: - LocalItem model

struct LocalItem: Identifiable, Hashable {
    let id = UUID()
    let url:          URL
    let name:         String
    let isDirectory:  Bool
    let fileSize:     Int64
    let modifiedDate: Date

    var sizeString: String {
        if isDirectory { return "" }
        let sz = fileSize
        if sz < 1024         { return "\(sz) B" }
        if sz < 1024*1024    { return String(format: "%.1f KB", Double(sz)/1024) }
        return String(format: "%.1f MB", Double(sz)/(1024*1024))
    }

    var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yy HH:mm"
        return f.string(from: modifiedDate)
    }

    var systemImage: String {
        isDirectory ? "folder.fill" : sfSymbol(for: url.pathExtension)
    }

    private func sfSymbol(for ext: String) -> String {
        switch ext.lowercased() {
        case "st", "msa":  return "opticaldisc"
        case "txt", "md":  return "doc.text"
        case "png", "jpg", "gif", "neo", "pi1", "pi2", "pi3":
            return "photo"
        case "prg", "tos", "ttp": return "cpu"
        default: return "doc"
        }
    }

    static func == (lhs: LocalItem, rhs: LocalItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
