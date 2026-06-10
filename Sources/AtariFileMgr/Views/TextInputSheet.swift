// TextInputSheet.swift — AtariFileMgr
// Reusable text input dialog as a proper Sheet.
//
// Background: SwiftUI's .alert() with TextField does not work reliably
// on macOS — the first responder status gets lost and keyboard inputs
// are not forwarded. A real sheet window with @FocusState fully resolves this.

import SwiftUI

struct TextInputSheet: View {
    let title: String
    let message: String
    let placeholder: String
    let confirmLabel: String
    @Binding var isPresented: Bool
    let onConfirm: (String) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        title: String,
        message: String = "",
        placeholder: String = "",
        confirmLabel: String = "OK",
        initialText: String = "",
        isPresented: Binding<Bool>,
        onConfirm: @escaping (String) -> Void
    ) {
        self.title        = title
        self.message      = message
        self.placeholder  = placeholder
        self.confirmLabel = confirmLabel
        self._text        = State(initialValue: initialText)
        self._isPresented = isPresented
        self.onConfirm    = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(title)
                .font(.headline)

            // Optional description
            if !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Input field — focused via @FocusState as soon as the sheet appears
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onConfirm(text.trimmingCharacters(in: .whitespaces))
                    isPresented = false
                }

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button(confirmLabel) {
                    onConfirm(text.trimmingCharacters(in: .whitespaces))
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        // Focus immediately when sheet appears
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
}
