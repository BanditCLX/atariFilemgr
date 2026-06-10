// UnsavedChangesDialog.swift — AtariFileMgr
// Native macOS confirmation dialog for unsaved changes.
// Integrated via Swift Concurrency (CheckedContinuation) to prevent data loss
// when creating, opening, or closing disk images.

import AppKit

enum UnsavedChangesDialog {

    /// Checks if there are unsaved changes and warns the user.
    /// Returns `true` if it is safe to proceed (either because the file wasn't modified
    /// or the user explicitly discards the changes). Returns `false` if cancelled.
    @MainActor
    static func confirmDiscardIfDirty(isDirty: Bool) async -> Bool {
        guard isDirty else { return true }
        
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Unsaved Changes"
            alert.informativeText = "You have unsaved changes in the current disk image. Do you want to discard them and continue?"
            alert.alertStyle = .warning
            
            alert.addButton(withTitle: "Discard & Continue") // Index 0 (alertFirstButtonReturn)
            alert.addButton(withTitle: "Cancel")             // Index 1 (alertSecondButtonReturn)
            
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
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
