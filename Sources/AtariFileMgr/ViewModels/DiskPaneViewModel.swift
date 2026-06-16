// DiskPaneViewModel.swift — AtariFileMgr
// ViewModel for the right pane: browsing the open Atari ST disk image.

import Foundation
import SwiftUI

@MainActor
final class DiskPaneViewModel: ObservableObject {

    // MARK: - Published state

    @Published var entries: [GEMDOSEntry] = []
    @Published var selectedEntries: Set<GEMDOSEntry> = []
    @Published var currentCluster: UInt16 = 0  // 0 = root directory
    @Published var breadcrumbs: [(name: String, cluster: UInt16)] = [("/ (root)", 0)]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var sortColumn: SortColumn = .name
    @Published var sortAscending: Bool = true

    // MARK: - Dependency

    private weak var appVM: AppViewModel?

    enum SortColumn { case name, size, date, attr }

    // MARK: - Init

    init(appViewModel: AppViewModel) {
        self.appVM = appViewModel
    }

    // MARK: - Filesystem access

    private var fs: GEMDOSFilesystem? { appVM?.filesystem }

    // MARK: - Navigation

    func navigateTo(entry: GEMDOSEntry) {
        guard entry.isDirectory else { return }
        breadcrumbs.append((entry.displayName, entry.startCluster))
        currentCluster = entry.startCluster
        refresh()
    }

    func navigateToRoot() {
        breadcrumbs = [("/ (root)", 0)]
        currentCluster = 0
        refresh()
    }

    func navigateToBreadcrumb(index: Int) {
        guard index < breadcrumbs.count else { return }
        breadcrumbs = Array(breadcrumbs.prefix(index + 1))
        currentCluster = breadcrumbs[index].cluster
        refresh()
    }

    func goUp() {
        guard breadcrumbs.count > 1 else { return }
        breadcrumbs.removeLast()
        currentCluster = breadcrumbs.last?.cluster ?? 0
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        guard let fs else {
            entries = []
            return
        }
        isLoading = true
        Task {
            do {
                let raw: [GEMDOSEntry]
                if currentCluster == 0 {
                    raw = try fs.listRootDirectory()
                } else {
                    raw = try fs.listDirectory(cluster: currentCluster)
                }
                self.entries = sort(raw)
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Sorting

    func sort(_ items: [GEMDOSEntry]) -> [GEMDOSEntry] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let result: Bool
            switch sortColumn {
            case .name: result = a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            case .size: result = a.fileSize < b.fileSize
            case .date: result = a.fatDate < b.fatDate || (a.fatDate == b.fatDate && a.fatTime < b.fatTime)
            case .attr: result = a.attributes.rawValue < b.attributes.rawValue
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
        entries = sort(entries)
    }

    // MARK: - File operations

    /// Import a local file or directory into the current disk directory.
    func importFile(url: URL) async throws {
        try await importFile(url: url, intoCluster: currentCluster)
    }

    /// Import a local file or directory (recursively) into a specific directory cluster.
    func importFile(url: URL, intoCluster cluster: UInt16) async throws {
        guard let fs else { return }
        
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        let values = try url.resourceValues(forKeys: keys)
        let isDir = values.isDirectory ?? false
        let name = Filename83.sanitise(url.lastPathComponent)
        
        // ── Overwrite Check ──
        let existing = try (cluster == 0 ? fs.listRootDirectory() : fs.listDirectory(cluster: cluster))
        if let duplicate = existing.first(where: { $0.displayName.uppercased() == name.uppercased() }) {
            let shouldOverwrite = await OverwriteDialog.ask(fileName: name)
            if !shouldOverwrite { return }
            // Delete the duplicate first before writing
            try fs.delete(duplicate)
        }
        
        if isDir {
            // 1. Create directory on disk
            let subEntry = try fs.createDirectory(name: name, inDirectoryCluster: cluster)
            // 2. Read local directory contents
            let localContents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            // 3. Recursively import local sub-items
            for subURL in localContents {
                try await importFile(url: subURL, intoCluster: subEntry.startCluster)
            }
        } else {
            // Standard file import
            let data = try Data(contentsOf: url)
            try fs.writeFile(name: name, data: data, inDirectoryCluster: cluster)
        }
        appVM?.isDirty = true
    }

    /// Import multiple local files or directories into the current directory.
    func importFiles(urls: [URL]) {
        importFiles(urls: urls, intoCluster: currentCluster)
    }

    /// Import multiple local files or directories into a specific directory cluster.
    func importFiles(urls: [URL], intoCluster cluster: UInt16) {
        Task {
            isLoading = true
            do {
                for url in urls {
                    try await importFile(url: url, intoCluster: cluster)
                }
                self.refresh()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Move a disk entry into a different directory cluster.
    func moveEntry(_ entry: GEMDOSEntry, intoCluster destCluster: UInt16) {
        guard let fs else { return }
        // Don't move into itself or its own cluster
        guard entry.startCluster != destCluster else { return }
        Task {
            do {
                if entry.isDirectory {
                    // For directory, we move by updating its directory entry (moving dir not fully supported,
                    // but we can recreate or if fs layer supports rename/move. Here we recreate or fail)
                    // Let's call copy-move or directory move. Since it's a directory, move requires rewriting its parent dir.
                    // Actually, moving files within a FAT12 directory is simple: we change its directory entry position!
                    // Let's implement moving entry: GEMDOSFilesystem has no move method, but we can do readFile/writeFile.
                    // Wait, we can copyFile/delete for files. Since it's simple:
                    // standard copyFile for folders is recursive, let's see.
                    // To keep it simple and robust, let's do file move:
                    let subDirEntry = try fs.createDirectory(name: entry.displayName, inDirectoryCluster: destCluster)
                    try await moveDirectoryContents(fromCluster: entry.startCluster, toCluster: subDirEntry.startCluster)
                    try fs.delete(entry)
                } else {
                    let data = try fs.readFile(entry)
                    try fs.writeFile(name: entry.displayName, data: data, inDirectoryCluster: destCluster)
                    try fs.delete(entry)
                }
                appVM?.isDirty = true
                self.refresh()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func moveDirectoryContents(fromCluster srcCluster: UInt16, toCluster destCluster: UInt16) async throws {
        guard let fs = fs else { return }
        let subEntries = try fs.listDirectory(cluster: srcCluster)
        for entry in subEntries {
            if entry.isDirectory {
                let subDirEntry = try fs.createDirectory(name: entry.displayName, inDirectoryCluster: destCluster)
                try await moveDirectoryContents(fromCluster: entry.startCluster, toCluster: subDirEntry.startCluster)
                try fs.delete(entry)
            } else {
                let data = try fs.readFile(entry)
                try fs.writeFile(name: entry.displayName, data: data, inDirectoryCluster: destCluster)
                try fs.delete(entry)
            }
        }
    }

    /// Extract a disk entry (file or folder recursively) to a local directory URL.
    func extractEntry(_ entry: GEMDOSEntry, to destDir: URL) async throws {
        guard let fs else { return }
        let destURL = destDir.appendingPathComponent(entry.displayName)
        
        // ── Overwrite Check ──
        if FileManager.default.fileExists(atPath: destURL.path) {
            let shouldOverwrite = await OverwriteDialog.ask(fileName: entry.displayName)
            if !shouldOverwrite { return }
            // Delete existing file/directory on host
            try FileManager.default.removeItem(at: destURL)
        }
        
        if entry.isDirectory {
            // 1. Create local directory
            try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
            // 2. Read sub-entries from disk and recursively extract them
            let subEntries = try fs.listDirectory(cluster: entry.startCluster)
            for sub in subEntries {
                try await extractEntry(sub, to: destURL)
            }
        } else {
            let data = try getFileDataForExport(entry)
            try data.write(to: destURL)
        }
    }

    /// Prepare a temporary local URL for dragging a disk entry out of the app.
    func prepareDragURL(for entry: GEMDOSEntry) -> URL? {
        guard self.fs != nil else { return nil }
        do {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(entry.id.uuidString)
            // Clean up previous if exists
            try? FileManager.default.removeItem(at: tempDir)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let tempURL = tempDir.appendingPathComponent(entry.displayName)
            
            if entry.isDirectory {
                try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
                try exportDirectory(entry, to: tempURL)
            } else {
                let data = try getFileDataForExport(entry)
                try data.write(to: tempURL)
            }
            return tempURL
        } catch {
            print("Failed to prepare drag URL: \(error)")
            return nil
        }
    }

    /// Prepare multiple temporary local URLs for dragging multiple disk entries out of the app.
    func prepareDragURLs(for entries: [GEMDOSEntry]) -> [URL] {
        var urls: [URL] = []
        for entry in entries {
            if let url = prepareDragURL(for: entry) {
                urls.append(url)
            }
        }
        return urls
    }

    private func getFileDataForExport(_ entry: GEMDOSEntry) throws -> Data {
        guard let fs else { throw NSError(domain: "AtariFileMgr", code: 1, userInfo: [NSLocalizedDescriptionKey: "No filesystem"]) }
        var data = try fs.readFile(entry)
        if let prefix = try? fs.readFilePrefix(entry, maxLength: 512),
           let format = AtariCompressionDetector.detect(data: prefix),
           format.name.contains("Pack-Ice") {
            if let decompressed = SwiftPackIce.decompress(data: data) {
                data = decompressed
            }
        }
        return data
    }

    /// Recursively export a directory entry from the GEMDOS filesystem to a local URL.
    private func exportDirectory(_ entry: GEMDOSEntry, to localDir: URL) throws {
        guard let fs else { return }
        let subEntries = try fs.listDirectory(cluster: entry.startCluster)
        for sub in subEntries {
            let destURL = localDir.appendingPathComponent(sub.displayName)
            if sub.isDirectory {
                try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
                try exportDirectory(sub, to: destURL)
            } else {
                let data = try getFileDataForExport(sub)
                try data.write(to: destURL)
            }
        }
    }

    /// Delete selected entries.
    func deleteSelected() {
        guard let fs else { return }
        let toDelete = selectedEntries
        Task {
            do {
                for entry in toDelete {
                    try fs.delete(entry)
                }
                selectedEntries.removeAll()
                appVM?.isDirty = true
                self.refresh()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Rename an entry.
    func rename(_ entry: GEMDOSEntry, to newName: String) {
        guard let fs else { return }
        Task {
            do {
                try fs.rename(entry, to: newName)
                appVM?.isDirty = true
                self.refresh()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Create a new directory.
    func createDirectory(name: String) {
        guard let fs else { return }
        Task {
            do {
                try fs.createDirectory(name: name, inDirectoryCluster: currentCluster)
                appVM?.isDirty = true
                self.refresh()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Disk info helpers

    var diskInfoString: String {
        guard let fs else { return "No disk loaded" }
        let freeKB = fs.freeBytes / 1024
        let totalKB = fs.totalBytes / 1024
        let geo = fs.image.geometry
        let fileCount = entries.filter(\.isFile).count
        let dirCount  = entries.filter(\.isDirectory).count
        return "\(freeKB) KB free of \(totalKB) KB · \(fileCount) files, \(dirCount) dirs · \(geo.description)"
    }
}
