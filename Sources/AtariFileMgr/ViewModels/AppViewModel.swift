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
