// AtariFileMgrApp.swift — AtariFileMgr
// Application entry point. Sets up the main window and shared environment objects.

import SwiftUI
import AppKit

// MARK: - AppDelegate
// Critical: Without an explicit AppDelegate and NSApp.activate(), the
// app does not receive keyboard events when launched via 'swift run',
// as macOS does not automatically set the activationPolicy to .regular.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register as a normal GUI app (dock icon, menu bar, keyboard input)
        NSApp.setActivationPolicy(.regular)
        // Bring window to foreground and activate keyboard events
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let appVM = AppViewModel.shared
        guard appVM.isDirty, let img = appVM.openDiskImage else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made in the disk image?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")       // First button (.alertFirstButtonReturn)
        alert.addButton(withTitle: "Cancel")     // Second button (.alertSecondButtonReturn)
        alert.addButton(withTitle: "Don't Save") // Third button (.alertThirdButtonReturn)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Save
            if let url = appVM.diskSourceURL {
                let ext = url.pathExtension.lowercased()
                if ext == "dim" || ext == "ahd" {
                    handleSaveAsOnQuit(appVM: appVM)
                    return .terminateLater
                }
                
                do {
                    try img.save(to: url)
                    appVM.isDirty = false
                    return .terminateNow
                } catch {
                    appVM.presentError(error)
                    return .terminateCancel
                }
            } else {
                handleSaveAsOnQuit(appVM: appVM)
                return .terminateLater
            }

        case .alertSecondButtonReturn: // Cancel
            return .terminateCancel

        case .alertThirdButtonReturn: // Don't Save
            return .terminateNow

        default:
            return .terminateCancel
        }
    }

    private func handleSaveAsOnQuit(appVM: AppViewModel) {
        let suggestedName = appVM.diskSourceURL?.lastPathComponent ?? "NewDisk.st"
        SavePanel.show(suggestedName: suggestedName) { url in
            guard let url else {
                NSApp.reply(toApplicationShouldTerminate: false)
                return
            }
            
            Task {
                do {
                    guard let img = appVM.openDiskImage else {
                        NSApp.reply(toApplicationShouldTerminate: false)
                        return
                    }
                    let ext = url.pathExtension.lowercased()
                    if ext == "msa" && !(img is MSADiskImage) {
                        let rawData = try img.rawData()
                        let msaImage = MSADiskImage(geometry: img.geometry)
                        try msaImage.writeAll(from: rawData)
                        try msaImage.save(to: url)
                        appVM.openDiskImage = msaImage
                    } else if ext == "st" && !(img is STDiskImage) {
                        let rawData = try img.rawData()
                        let stImage = STDiskImage(geometry: img.geometry)
                        try stImage.writeAll(from: rawData)
                        try stImage.save(to: url)
                        appVM.openDiskImage = stImage
                    } else {
                        try img.save(to: url)
                        if ext == "st", let stImg = img as? STDiskImage {
                            stImg.formatName = "ST (raw)"
                        }
                    }
                    appVM.diskSourceURL = url
                    appVM.isDirty = false
                    NSApp.reply(toApplicationShouldTerminate: true)
                } catch {
                    appVM.presentError(error)
                    NSApp.reply(toApplicationShouldTerminate: false)
                }
            }
        }
    }
}

// MARK: - App

@main
struct AtariFileMgrApp: App {

    @StateObject private var appVM = AppViewModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appVM)
                .frame(minWidth: 900, minHeight: 550)
                .onOpenURL { url in
                    appVM.openDisk(url: url)
                }
        }
        .commands {
            AppCommands()
        }
    }
}

// MARK: - Menu commands

struct AppCommands: Commands {
    @Environment(\.openURL) var openURL

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Disk Image…") {
                NotificationCenter.default.post(name: .showNewDisk, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                AppViewModel.shared.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!AppViewModel.shared.isDirty)

            Button("Save As…") {
                NotificationCenter.default.post(name: .showSaveAs, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandMenu("Disk") {
            Button("Open Disk Image…") {
                NotificationCenter.default.post(name: .showOpenDisk, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Close Disk") {
                AppViewModel.shared.closeDisk()
            }
            .disabled(AppViewModel.shared.openDiskImage == nil)
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let showNewDisk  = Notification.Name("showNewDisk")
    static let showOpenDisk = Notification.Name("showOpenDisk")
    static let showSaveAs   = Notification.Name("showSaveAs")
    static let diskLoaded   = Notification.Name("diskLoaded")
}
