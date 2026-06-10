// AtariFileMgrApp.swift — AtariFileMgr
// Application entry point. Sets up the main window and shared environment objects.

import SwiftUI
import AppKit

// MARK: - AppDelegate
// Critical: Without an explicit AppDelegate and NSApp.activate(), the
// app does not receive keyboard events when launched via 'swift run',
// as macOS does not automatically set the activationPolicy to .regular.

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
