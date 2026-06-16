// SavePanel.swift — AtariFileMgr
// AppKit Bridge: opens a native NSSavePanel for "Save As".
//
// Background: SwiftUI's .fileMover() only works for already
// existing files (it moves them). For new, never-saved
// images, NSSavePanel must be called directly.

import AppKit
import UniformTypeIdentifiers

enum SavePanel {

    /// Opens a modal NSSavePanel and calls `completion` with the
    /// selected URL, or nil if the user cancels.
    @MainActor
    static func show(
        suggestedName: String = "NewDisk.st",
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "Save Disk Image As..."
        panel.nameFieldLabel = "Save As:"
        
        // Use the pure base name without extension for the name field,
        // so macOS appends and manages the extension natively.
        let baseName = (suggestedName as NSString).deletingPathExtension
        panel.nameFieldStringValue = baseName
        
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        // ── Native macOS Accessory View for Format Selection ──
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 40))

        let label = NSTextField(labelWithString: "Format:")
        label.frame = NSRect(x: 10, y: 10, width: 80, height: 20)
        label.font = NSFont.systemFont(ofSize: 12)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        container.addSubview(label)

        let popUp = NSPopUpButton(frame: NSRect(x: 95, y: 8, width: 215, height: 25), pullsDown: false)
        popUp.addItems(withTitles: ["Atari ST Disk Image (.st)", "Magic Shadow Archiver (.msa)"])
        container.addSubview(popUp)

        let formatTarget = FormatSelectorTarget(panel: panel, popUp: popUp)
        
        // Determine initial file type based on file extension
        let isMSA = suggestedName.lowercased().hasSuffix(".msa")
        if isMSA {
            popUp.selectItem(at: 1)
            if let msaType = UTType(filenameExtension: "msa") {
                panel.allowedContentTypes = [msaType]
            }
        } else {
            popUp.selectItem(at: 0)
            if let stType = UTType(filenameExtension: "st") {
                panel.allowedContentTypes = [stType]
            }
        }

        panel.accessoryView = container

        // Show modally on the key window
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                _ = formatTarget // Keep the target in memory
                completion(response == .OK ? panel.url : nil)
            }
        } else {
            panel.begin { response in
                _ = formatTarget // Keep the target in memory
                completion(response == .OK ? panel.url : nil)
            }
        }
    }
}

// MARK: - FormatSelectorTarget

final class FormatSelectorTarget: NSObject {
    weak var panel: NSSavePanel?
    weak var popUp: NSPopUpButton?

    init(panel: NSSavePanel, popUp: NSPopUpButton) {
        self.panel = panel
        self.popUp = popUp
        super.init()
        popUp.target = self
        popUp.action = #selector(formatChanged(_:))
    }

    @objc func formatChanged(_ sender: NSPopUpButton) {
        guard let panel else { return }
        let ext = sender.indexOfSelectedItem == 0 ? "st" : "msa"
        if let type = UTType(filenameExtension: ext) {
            // By changing allowedContentTypes, macOS automatically and
            // correctly updates the file extension in the save dialog.
            panel.allowedContentTypes = [type]
        }
    }
}

// MARK: - OpenPanel (Open Disk Image)

enum OpenPanel {

    @MainActor
    static func show(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Open Disk Image"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        var types: [UTType] = []
        if let st  = UTType(filenameExtension: "st")  { types.append(st) }
        if let msa = UTType(filenameExtension: "msa") { types.append(msa) }
        if let dim = UTType(filenameExtension: "dim") { types.append(dim) }
        if let ahd = UTType(filenameExtension: "ahd") { types.append(ahd) }
        if let stx = UTType(filenameExtension: "stx") { types.append(stx) }
        if types.isEmpty { types = [.data] }
        panel.allowedContentTypes = types

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                completion(response == .OK ? panel.url : nil)
            }
        } else {
            panel.begin { response in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }
}
