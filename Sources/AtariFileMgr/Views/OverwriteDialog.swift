// OverwriteDialog.swift — AtariFileMgr
// Native macOS confirmation dialog for overwriting files/folders.
// Uses modern Swift Concurrency (CheckedContinuation) to seamlessly integrate
// into asynchronous copy loops.

import AppKit

enum OverwriteDialog {

    /// Displays a native macOS warning sheet asking if an item should be overwritten.
    /// Returns `true` if the user clicks "Overwrite", otherwise `false`.
    @MainActor
    static func ask(fileName: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Overwrite item?"
            alert.informativeText = "An item named '\(fileName)' already exists in the destination folder. Do you want to overwrite it?"
            alert.alertStyle = .warning
            
            alert.addButton(withTitle: "Overwrite") // Index 0 (alertFirstButtonReturn)
            alert.addButton(withTitle: "Cancel")    // Index 1 (alertSecondButtonReturn)
            
            // Attach as a sheet to the key window (asynchronous → no event lock)
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
                // Fallback: Modal dialog
                let response = alert.runModal()
                continuation.resume(returning: response == .alertFirstButtonReturn)
                return
            }
            
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }
}
