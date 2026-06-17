// AtariSTImageViewerSheet.swift — AtariFileMgr
// SwiftUI preview modal for retro Atari ST graphic files.

import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import ObjectiveC
import AppKit

struct AtariSTImageViewerSheet: View {
    let filename: String
    let fileData: Data

    @State private var decodedImage: DecodedAtariSTImage? = nil
    @State private var zoomScale: CGFloat = 2.0
    @State private var isFitToWindow: Bool = true
    @State private var hasFailed = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false

    @State private var textContents: String = ""
    @State private var textTheme: TextTheme = .greenScreen

    private var isTextFile: Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["txt", "s", "diz", "lst", "bas", "asm", "src", "c", "h", "pas", "doc", "asc", "ata", "hlp", "inf", "cfg"].contains(ext)
    }

    enum TextTheme: String, CaseIterable, Identifiable {
        case greenScreen = "Green Screen"
        case amberScreen = "Amber Screen"
        case gemDefault = "GEM Default"
        
        var id: String { self.rawValue }
        
        var textColor: Color {
            switch self {
            case .greenScreen: return .green
            case .amberScreen: return .orange
            case .gemDefault: return .black
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .greenScreen, .amberScreen: return Color(white: 0.08)
            case .gemDefault: return .white
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    if isTextFile {
                        Text("ASCII Text Document  •  \(fileData.count) bytes")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else if let img = decodedImage {
                        Text("\(img.formatName)  •  \(img.resolutionText)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else if hasFailed {
                        Text("Supported formats: DEGAS, NEOchrome, STAD, Spectrum 512 (SPU/SPC), PhotoChrome (PCS)")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    } else {
                        Text("Decoding bitplanes...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { AtariSTImageViewerWindowManager.shared.close() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Canvas Area
            ZStack {
                if isTextFile {
                    ScrollView([.horizontal, .vertical]) {
                        Text(textContents)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(textTheme.textColor)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .background(textTheme.backgroundColor)
                } else if let decoded = decodedImage {
                    let nsImg = NSImage(cgImage: decoded.cgImage, size: NSSize(width: decoded.cgImage.width, height: decoded.cgImage.height))
                    
                    ScrollView([.horizontal, .vertical]) {
                        VStack {
                            Image(nsImage: nsImg)
                                .resizable()
                                .interpolation(.none) // retro-crisp rendering
                                .aspectRatio(contentMode: isFitToWindow ? .fit : .fill)
                                .frame(
                                    width: isFitToWindow ? nil : CGFloat(decoded.cgImage.width) * zoomScale,
                                    height: isFitToWindow ? nil : CGFloat(decoded.cgImage.height) * zoomScale
                                )
                                .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(Color.black)
                } else if hasFailed {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Failed to Decode Image")
                            .font(.system(size: 14, weight: .semibold))
                        Text("This file might be corrupted or its format is not supported.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Decoding Atari ST Planar Data...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer controls and color blocks
            HStack(alignment: .center) {
                if isTextFile {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Terminal Theme")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Picker("", selection: $textTheme) {
                            ForEach(TextTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 260)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(textContents, forType: .string)
                    }) {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                } else {
                    // Palette list
                    if let decoded = decodedImage, !decoded.palette.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Palette Colors")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 3), count: 8), alignment: .leading, spacing: 3) {
                                ForEach(0..<decoded.palette.count, id: \.self) { idx in
                                    let argb = decoded.palette[idx]
                                    let r = Double((argb >> 16) & 0xFF) / 255.0
                                    let g = Double((argb >> 8) & 0xFF) / 255.0
                                    let b = Double(argb & 0xFF) / 255.0
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(red: r, green: g, blue: b))
                                        .frame(width: 14, height: 14)
                                        .help("Color index \(idx)")
                                }
                            }
                        }
                    }

                    Spacer()

                    // Action controls grouped horizontally on the right
                    HStack(spacing: 12) {
                        if let decoded = decodedImage {
                            Button(action: {
                                saveAsPNG(decoded: decoded)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Save as PNG...")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }

                        if decodedImage != nil {
                            Picker("", selection: $isFitToWindow) {
                                Text("Scale to Fit").tag(true)
                                Text("Custom Zoom").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 160)

                            if !isFitToWindow {
                                HStack(spacing: 6) {
                                    Text("Zoom:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Slider(value: $zoomScale, in: 1...8, step: 1)
                                        .frame(width: 80)
                                    Text("\(Int(zoomScale))x")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .frame(width: 24, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 500, idealWidth: 700, maxWidth: .infinity, minHeight: 420, idealHeight: 550, maxHeight: .infinity)
        .onAppear {
            if isTextFile {
                decodeTextFile()
            } else {
                decodeImageFile()
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Save Failed"),
                message: Text(errorMessage ?? "An unknown error occurred while saving the image."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func decodeImageFile() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let decoded = AtariSTImageDecoder.decode(data: fileData, filename: filename) {
                DispatchQueue.main.async {
                    self.decodedImage = decoded
                }
            } else {
                DispatchQueue.main.async {
                    self.hasFailed = true
                }
            }
        }
    }

    private func decodeTextFile() {
        var targetData = fileData
        if fileData.count >= 12 {
            let sig = fileData.prefix(4)
            if sig == Data([0x49, 0x63, 0x65, 0x21]) || sig == Data([0x49, 0x43, 0x45, 0x21]) {
                if let decompressed = AtariSTImageDecoder.decompressPackIce(data: fileData) {
                    targetData = decompressed
                }
            }
        }
        
        let text = String(data: targetData, encoding: .utf8) ?? String(data: targetData, encoding: .isoLatin1) ?? "Undecodable text format."
        self.textContents = text
    }

    private func saveAsPNG(decoded: DecodedAtariSTImage) {
        SavePanel.showPNG(suggestedName: filename) { url in
            guard let url = url else { return }
            
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                self.errorMessage = "Could not create image destination writer for \(url.lastPathComponent)."
                self.showErrorAlert = true
                return
            }
            
            CGImageDestinationAddImage(destination, decoded.cgImage, nil)
            if !CGImageDestinationFinalize(destination) {
                self.errorMessage = "Failed to finalize and write PNG data to disk."
                self.showErrorAlert = true
            }
        }
    }
}

// Grid background pattern for transparent/opaque backgrounds
struct ImageGridBackground: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let size: CGFloat = 12
                let cols = Int(geo.size.width / size) + 1
                let rows = Int(geo.size.height / size) + 1
                for r in 0..<rows {
                    for c in 0..<cols {
                        if (r + c) % 2 == 0 {
                            path.addRect(CGRect(x: CGFloat(c) * size, y: CGFloat(r) * size, width: size, height: size))
                        }
                    }
                }
            }
            .fill(Color(white: 0.16))
            .background(Color(white: 0.22))
        }
    }
}

public final class AtariSTImageViewerWindowManager: NSObject, NSWindowDelegate {
    public static let shared = AtariSTImageViewerWindowManager()
    
    private var window: NSWindow?
    private var contentController: NSHostingController<AtariSTImageViewerSheet>?
    
    public func show(filename: String, fileData: Data) {
        if let window = self.window {
            let sheetView = AtariSTImageViewerSheet(
                filename: filename,
                fileData: fileData
            )
            window.contentView = NSHostingView(rootView: sheetView)
            window.title = filename
            window.makeKeyAndOrderFront(nil)
        } else {
            let sheetView = AtariSTImageViewerSheet(
                filename: filename,
                fileData: fileData
            )
            let hostingController = NSHostingController(rootView: sheetView)
            self.contentController = hostingController
            
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = filename
            win.contentViewController = hostingController
            win.minSize = NSSize(width: 500, height: 420)
            win.center()
            win.setFrameAutosaveName("AtariSTImageViewerWindow")
            win.delegate = self
            
            self.window = win
            win.makeKeyAndOrderFront(nil)
        }
    }
    
    public func close() {
        guard let win = self.window else { return }
        
        // Break references immediately before closing/releasing to prevent dealloc crash
        win.contentViewController = nil
        win.contentView = nil
        win.delegate = nil
        win.close()
        
        let controller = self.contentController
        self.window = nil
        self.contentController = nil
        
        DispatchQueue.main.async {
            AppViewModel.shared.showViewer = false
            _ = win
            _ = controller
        }
    }
    
    public func windowWillClose(_ notification: Notification) {
        guard let win = self.window else { return }
        
        // Break references immediately before closing/releasing to prevent dealloc crash
        win.contentViewController = nil
        win.contentView = nil
        win.delegate = nil
        
        let controller = self.contentController
        self.window = nil
        self.contentController = nil
        
        DispatchQueue.main.async {
            AppViewModel.shared.showViewer = false
            _ = win
            _ = controller
        }
    }
}


