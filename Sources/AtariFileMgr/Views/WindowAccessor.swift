// WindowAccessor.swift — AtariFileMgr
// SwiftUI helper to access the underlying NSWindow and intercept window closing.

import SwiftUI
import AppKit
import ObjectiveC

private var proxyKey: UInt8 = 0

/// A SwiftUI view that accesses its parent NSWindow and sets up a delegate proxy
/// to intercept window closing when there are unsaved changes.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                setupWindowDelegate(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func setupWindowDelegate(_ window: NSWindow) {
        // Only set up proxy if not already done
        if objc_getAssociatedObject(window, &proxyKey) == nil {
            let proxy = WindowDelegateProxy(originalDelegate: window.delegate)
            objc_setAssociatedObject(window, &proxyKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            window.delegate = proxy
        }
    }
}

// MARK: - WindowDelegateProxy

final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var originalDelegate: NSWindowDelegate?

    init(originalDelegate: NSWindowDelegate?) {
        self.originalDelegate = originalDelegate
        super.init()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original = originalDelegate, original.responds(to: aSelector) {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }

    @MainActor
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let appVM = AppViewModel.shared
        guard appVM.isDirty, let img = appVM.openDiskImage else {
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made in the disk image?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")       // First button (.alertFirstButtonReturn)
        alert.addButton(withTitle: "Cancel")     // Second button (.alertSecondButtonReturn)
        alert.addButton(withTitle: "Don't Save") // Third button (.alertThirdButtonReturn)

        alert.beginSheetModal(for: sender) { response in
            switch response {
            case .alertFirstButtonReturn: // Save
                if let url = appVM.diskSourceURL {
                    let ext = url.pathExtension.lowercased()
                    if ext == "dim" || ext == "ahd" {
                        self.handleSaveAsOnClose(window: sender, appVM: appVM)
                    } else {
                        do {
                            try img.save(to: url)
                            appVM.isDirty = false
                            sender.close()
                        } catch {
                            appVM.presentError(error)
                        }
                    }
                } else {
                    self.handleSaveAsOnClose(window: sender, appVM: appVM)
                }

            case .alertSecondButtonReturn: // Cancel
                break

            case .alertThirdButtonReturn: // Don't Save
                appVM.isDirty = false
                sender.close()

            default:
                break
            }
        }
        
        // Return false to prevent window from closing immediately.
        // We will manually close it via window.close() upon confirmation.
        return false
    }

    @MainActor
    private func handleSaveAsOnClose(window: NSWindow, appVM: AppViewModel) {
        let suggestedName = appVM.diskSourceURL?.lastPathComponent ?? "NewDisk.st"
        SavePanel.show(suggestedName: suggestedName) { url in
            guard let url else { return }
            
            Task {
                do {
                    guard let img = appVM.openDiskImage else { return }
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
                    
                    window.close()
                } catch {
                    appVM.presentError(error)
                }
            }
        }
    }
}
