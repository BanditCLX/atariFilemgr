// TextInputDialog.swift — AtariFileMgr
// Native AppKit input dialog via NSAlert.beginSheetModal.
//
// Why beginSheetModal instead of runModal?
// - runModal() blocks synchronously from the SwiftUI button action context,
//   which prevents AppKit from correctly setting the first responder.
// - beginSheetModal() attaches the dialog asynchronously to the window (as a sheet),
//   after SwiftUI has completed its event cycle — this guarantees the text field
//   gets focus and keyboard inputs work properly.

import AppKit

enum TextInputDialog {

    /// Shows a native macOS sheet dialog with a text field.
    /// The result is returned asynchronously via a completion handler.
    @MainActor
    static func show(
        title: String,
        message: String = "",
        placeholder: String = "",
        defaultValue: String = "",
        confirmLabel: String = "OK",
        completion: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText   = title
        alert.alertStyle    = .informational
        if !message.isEmpty {
            alert.informativeText = message
        }
        alert.addButton(withTitle: confirmLabel)   // Index 0 → .alertFirstButtonReturn
        alert.addButton(withTitle: "Cancel")       // Index 1

        // NSTextField as input field
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = placeholder
        textField.stringValue       = defaultValue
        textField.bezelStyle        = .roundedBezel
        textField.cell?.wraps       = false
        textField.cell?.isScrollable = true
        alert.accessoryView = textField

        // initialFirstResponder → TextField receives focus as soon as the sheet appears
        alert.window.initialFirstResponder = textField

        // Attach as a sheet to the key window (asynchronous → no SwiftUI event lock)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            // Fallback: runModal if no window found
            let response = alert.runModal()
            let value = textField.stringValue.trimmingCharacters(in: .whitespaces)
            completion(response == .alertFirstButtonReturn && !value.isEmpty ? value : nil)
            return
        }

        alert.beginSheetModal(for: window) { response in
            let value = textField.stringValue.trimmingCharacters(in: .whitespaces)
            completion(response == .alertFirstButtonReturn && !value.isEmpty ? value : nil)
        }
    }
}
