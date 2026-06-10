// ReadOnlyFormatDialog.swift — AtariFileMgr
// Native macOS alert dialog for read-only disk image formats (.dim and .ahd).
// Shows a message that these formats are supported for opening only, and
// saving must be done in .st or .msa formats.

import AppKit

enum ReadOnlyFormatDialog {

    /// Present a native macOS modal sheet informing the user that the loaded file
    /// format is read-only and saving will require .st or .msa format.
    @MainActor
    static func showWarning(formatName: String) async {
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Read-Only Format (\(formatName))"
            alert.informativeText = "The \(formatName) file format is supported for opening only. Saving directly back to this format is not supported.\n\nTo save any changes, you will be required to 'Save As' a standard Atari ST (.st) or Magic Shadow Archiver (.msa) file."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")

            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
                _ = alert.runModal()
                continuation.resume()
                return
            }

            alert.beginSheetModal(for: window) { _ in
                continuation.resume()
            }
        }
    }
}
