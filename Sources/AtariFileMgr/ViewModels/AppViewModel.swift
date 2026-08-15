// AppViewModel.swift — AtariFileMgr
// Global application state: manages open disk images, recent files, undo/redo, errors.

import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Published state

    @Published var openDiskImage: (any DiskImage)?
    @Published var filesystem: GEMDOSFilesystem?
    @Published var diskSourceURL: URL?
    @Published var isDirty: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var recentFiles: [URL] = []
    @Published var isLoading: Bool = false
    
    // MARK: - Viewer State
    @Published var showViewer: Bool = false
    @Published var viewerImageName: String? = nil
    @Published var viewerImageData: Data? = nil
    @Published var viewerInitialMode: ViewMode = .image

    func viewFile(name: String, data: Data, initialMode: ViewMode? = nil) {
        self.viewerImageName = name
        self.viewerImageData = data
        self.viewerInitialMode = initialMode ?? ViewMode.bestMode(for: name, data: data)
        self.showViewer = true
    }

    func viewImage(name: String, data: Data, initialMode: ViewMode = .image) {
        self.viewFile(name: name, data: data, initialMode: initialMode)
    }

    func viewHex(name: String, data: Data) {
        self.viewFile(name: name, data: data, initialMode: .hexDump)
    }


    // MARK: - Undo/Redo (simple command-based)

    private var undoStack: [UndoableAction] = []
    private var redoStack: [UndoableAction] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Singleton / shared

    static let shared = AppViewModel()
    private init() {
        loadRecentFiles()
    }

    // MARK: - Open disk image

    /// Verifies if there are unsaved changes and returns whether it is safe to proceed.
    func checkDiscardChanges() async -> Bool {
        return await UnsavedChangesDialog.confirmDiscardIfDirty(isDirty: isDirty)
    }

    func openDisk(url: URL) {
        isLoading = true
        errorMessage = nil

        Task {
            let shouldProceed = await UnsavedChangesDialog.confirmDiscardIfDirty(isDirty: isDirty)
            guard shouldProceed else {
                isLoading = false
                return
            }

            do {
                let ext = url.pathExtension.lowercased()
                let isReadOnlyFormat = (ext == "dim" || ext == "ahd" || ext == "stx")

                let img: any DiskImage
                switch DiskImageFormat.detect(url: url) {
                case .st, .dim, .ahd:
                    img = try STDiskImage.load(from: url)
                case .msa:
                    img = try MSADiskImage.load(from: url)
                case .stx:
                    img = try STXDiskImage.load(from: url)
                case nil:
                    throw DiskImageError.invalidFormat("Unsupported file extension: \(url.pathExtension)")
                }
                let fs = try GEMDOSFilesystem(image: img)
                self.openDiskImage = img
                self.filesystem    = fs
                self.diskSourceURL = url
                self.isDirty       = false
                self.undoStack.removeAll()
                self.redoStack.removeAll()
                self.addToRecentFiles(url)
                self.isLoading = false
                NotificationCenter.default.post(name: .diskLoaded, object: nil)

                if isReadOnlyFormat {
                    // Show native warning box right after rendering finishes
                    await ReadOnlyFormatDialog.showWarning(formatName: ext.uppercased())
                }
            } catch {
                self.presentError(error)
                self.isLoading = false
            }
        }
    }

    // MARK: - New disk

    func newDisk(format: DiskFormat, volumeName: String) {
        Task {
            do {
                let geo = format.geometry
                let img = STDiskImage(geometry: geo)
                let fs  = try GEMDOSFilesystem.format(image: img, format: format, volumeName: volumeName)
                self.openDiskImage = img
                self.filesystem    = fs
                self.diskSourceURL = nil
                self.isDirty       = true
                self.undoStack.removeAll()
                self.redoStack.removeAll()
                NotificationCenter.default.post(name: .diskLoaded, object: nil)
            } catch {
                self.presentError(error)
            }
        }
    }

    func newDisk(geometry geo: DiskGeometry, volumeName: String) {
        Task {
            do {
                let img = STDiskImage(geometry: geo)
                let fs  = try GEMDOSFilesystem.format(image: img, geometry: geo, volumeName: volumeName)
                self.openDiskImage = img
                self.filesystem    = fs
                self.diskSourceURL = nil
                self.isDirty       = true
                self.undoStack.removeAll()
                self.redoStack.removeAll()
                NotificationCenter.default.post(name: .diskLoaded, object: nil)
            } catch {
                self.presentError(error)
            }
        }
    }

    // MARK: - Save

    func save() {
        guard let img = openDiskImage, let url = diskSourceURL else { return }
        let ext = url.pathExtension.lowercased()
        if ext == "dim" || ext == "ahd" {
            // Read-only format cannot be overwritten directly. Redirect to Save As
            NotificationCenter.default.post(name: .showSaveAs, object: nil)
            return
        }
        Task {
            do {
                try img.save(to: url)
                self.isDirty = false
            } catch {
                self.presentError(error)
            }
        }
    }

    func saveAs(url: URL) {
        guard let img = openDiskImage else { return }
        // If the extension changed (e.g. .st ↔ .msa), re-encode to the target format
        Task {
            do {
                let ext = url.pathExtension.lowercased()
                if ext == "msa" && !(img is MSADiskImage) {
                    // Convert to MSA (RLE compressed)
                    let rawData  = try img.rawData()
                    let msaImage = MSADiskImage(geometry: img.geometry)
                    try msaImage.writeAll(from: rawData)
                    try msaImage.save(to: url)
                    self.openDiskImage = msaImage
                } else if ext == "st" && !(img is STDiskImage) {
                    // Convert to ST (raw flat sectors)
                    let rawData = try img.rawData()
                    let stImage = STDiskImage(geometry: img.geometry)
                    try stImage.writeAll(from: rawData)
                    try stImage.save(to: url)
                    self.openDiskImage = stImage
                } else {
                    try img.save(to: url)
                    if ext == "st", let stImg = img as? STDiskImage {
                        // Reset formatName if saved from dim/ahd back to st
                        stImg.formatName = "ST (raw)"
                    }
                }
                self.diskSourceURL = url
                self.isDirty = false
                self.addToRecentFiles(url)
            } catch {
                self.presentError(error)
            }
        }
    }

    // MARK: - Close

    func closeDisk() {
        Task {
            let shouldProceed = await UnsavedChangesDialog.confirmDiscardIfDirty(isDirty: isDirty)
            guard shouldProceed else { return }
            
            openDiskImage = nil
            filesystem    = nil
            diskSourceURL = nil
            isDirty       = false
            undoStack.removeAll()
            redoStack.removeAll()
        }
    }

    // MARK: - Error presentation

    func presentError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    // MARK: - Recent files

    private let recentFilesKey = "RecentFiles"
    private let maxRecentFiles = 10

    func addToRecentFiles(_ url: URL) {
        var recent = recentFiles.filter { $0 != url }
        recent.insert(url, at: 0)
        recentFiles = Array(recent.prefix(maxRecentFiles))
        saveRecentFiles()
    }

    private func saveRecentFiles() {
        let paths = recentFiles.map(\.path)
        UserDefaults.standard.set(paths, forKey: recentFilesKey)
    }

    private func loadRecentFiles() {
        let paths = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        recentFiles = paths.map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

// MARK: - UndoableAction (placeholder for future undo support)

struct UndoableAction {
    let description: String
    let undo: () throws -> Void
    let redo: () throws -> Void
}

// MARK: - ViewMode

enum ViewMode: String, CaseIterable, Identifiable {
    case image = "Image"
    case text = "Text"
    case hexDump = "Hex Dump"
    
    var id: String { self.rawValue }

    static func bestMode(for filename: String, data: Data) -> ViewMode {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        // 1. Known Atari ST & standard graphic formats
        let imageExtensions: Set<String> = [
            "pi1", "pi2", "pi3",
            "pc1", "pc2", "pc3",
            "neo", "pac", "spu", "spc", "pcs",
            "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "icns"
        ]
        if imageExtensions.contains(ext) {
            return .image
        }
        
        // 2. Known Atari ST & common executable / binary formats -> Hex Dump
        let binaryExtensions: Set<String> = [
            "prg", "tos", "ttp", "acc", "gtp", "app",
            "dat", "snd", "bin", "raw", "rom", "o", "a",
            "rsc", "sav", "pak", "arc", "zip", "lzh", "zoo", "arj", "gz", "tar",
            "exe", "com", "dll", "so", "dylib", "elf", "ym", "mod", "mid", "midi"
        ]
        if binaryExtensions.contains(ext) {
            return .hexDump
        }
        
        // 3. Known text document / source code extensions -> Text
        let textExtensions: Set<String> = [
            "txt", "me", "diz", "lst", "bas", "asm", "s", "src", "c", "h", "pas",
            "doc", "asc", "ata", "hlp", "inf", "cfg", "ini", "log", "md", "json",
            "xml", "csv", "nfo", "mak", "def", "prj", "script", "sh", "zsh",
            "env", "yml", "yaml", "toml", "rtf", "html", "htm", "css", "js", "ts", "swift"
        ]
        if textExtensions.contains(ext) {
            return .text
        }
        
        // 4. Data inspection heuristics for unknown extensions:
        if data.starts(with: [112, 77, 56, 53]) || data.starts(with: [112, 77, 56, 54]) { // "pM85" or "pM86" STAD
            return .image
        }
        if data.count == 32034 || data.count == 51104 { // Degas or Spectrum 512 SPU
            return .image
        }

        // Check if binary (contains null bytes or high non-whitespace control char ratio)
        if isBinaryData(data) {
            return .hexDump
        } else {
            return .text
        }
    }

    private static func isBinaryData(_ data: Data) -> Bool {
        if data.isEmpty { return false }
        let checkLimit = min(data.count, 8000)
        var controlCount = 0
        for i in 0..<checkLimit {
            let byte = data[i]
            if byte == 0 { return true }
            if byte < 32 && byte != 9 && byte != 10 && byte != 13 {
                controlCount += 1
            }
        }
        let ratio = Double(controlCount) / Double(checkLimit)
        return ratio > 0.10
    }
}
