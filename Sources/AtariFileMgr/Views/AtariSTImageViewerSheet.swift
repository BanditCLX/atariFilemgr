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
    let initialMode: ViewMode

    @State private var viewMode: ViewMode = .image

    @State private var decodedImage: DecodedAtariSTImage? = nil
    @State private var zoomScale: CGFloat = 2.0
    @State private var isFitToWindow: Bool = true
    @State private var hasFailed = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false

    @State private var textContents: String = ""
    @State private var textTheme: TextTheme = .greenScreen
    @State private var textFormat: TextFormat = .rawText
    @State private var rawTextCache: String = ""
    @State private var asciiCleanedCache: String = ""
    @State private var findStringsCache: String = ""

    // Hex Editor / Chunk Extractor State
    @State private var hexFromInput: String = "0"
    @State private var hexToInput: String = ""
    @State private var chunkFilename: String = "chunk.bin"

    private var isTextFile: Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["txt", "me", "s", "diz", "lst", "bas", "asm", "src", "c", "h", "pas", "doc", "asc", "ata", "hlp", "inf", "cfg", "prg", "tos", "ttp", "acc"].contains(ext)
    }

    private var isImageFile: Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["pi1", "pi2", "pi3", "pc1", "pc2", "pc3", "neo", "pac", "spu", "spc", "pcs"].contains(ext)
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

    enum TextFormat: String, CaseIterable, Identifiable {
        case rawText = "RAW TEXT"
        case asciiCleaned = "ASCII CLEANED"
        case findStrings = "FIND STRINGS (strings >= 4ch)"
        
        var id: String { self.rawValue }
    }

    private var subtitleText: String {
        switch viewMode {
        case .image:
            if let img = decodedImage {
                return "\(img.formatName)  •  \(img.resolutionText)"
            } else if hasFailed {
                return "Failed to decode image"
            } else {
                return "Decoding bitplanes..."
            }
        case .text:
            return "ASCII Text Document  •  \(fileData.count) bytes"
        case .hexDump:
            return "Hex Dump  •  \(fileData.count) bytes"
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
                    Text(subtitleText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
                
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
                switch viewMode {
                case .image:
                    imageCanvas
                case .text:
                    textCanvas
                case .hexDump:
                    hexDumpCanvas
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer controls and color blocks
            HStack(alignment: .center) {
                switch viewMode {
                case .image:
                    imageFooter
                case .text:
                    textFooter
                case .hexDump:
                    hexDumpFooter
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 600, idealWidth: 750, maxWidth: .infinity, minHeight: 450, idealHeight: 550, maxHeight: .infinity)
        .onAppear {
            if initialMode == .image {
                if isTextFile {
                    viewMode = .text
                } else if isImageFile {
                    viewMode = .image
                } else {
                    viewMode = .hexDump
                }
            } else {
                viewMode = initialMode
            }

            hexToInput = "\(fileData.count)"
            chunkFilename = (filename as NSString).deletingPathExtension + ".chunk"

            decodeTextFile()
            decodeImageFile()
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Operation Failed"),
                message: Text(errorMessage ?? "An unknown error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Canvas Subviews

    private var imageCanvas: some View {
        ZStack {
            if let decoded = decodedImage {
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
    }

    private var textCanvas: some View {
        VStack(spacing: 0) {
            // Text View Format Selector
            HStack(spacing: 12) {
                Text("TEXT VIEW FORMAT:")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(textTheme.textColor)
                
                ForEach(TextFormat.allCases) { format in
                    Button(action: {
                        self.textFormat = format
                        self.updateDisplayedText()
                    }) {
                        Text(format.rawValue)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(self.textFormat == format ? textTheme.textColor : Color.clear)
                            .foregroundColor(self.textFormat == format ? textTheme.backgroundColor : textTheme.textColor)
                            .border(textTheme.textColor, width: self.textFormat == format ? 0 : 1)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(textTheme.backgroundColor)
            
            Divider()
                .background(textTheme.textColor.opacity(0.3))
            
            // Scrollable text content
            ScrollView([.horizontal, .vertical]) {
                Text(textContents)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(textTheme.textColor)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(textTheme.backgroundColor)
        }
        .background(textTheme.backgroundColor)
    }

    private var hexDumpCanvas: some View {
        HexDumpView(data: fileData, textColor: textTheme.textColor, backgroundColor: textTheme.backgroundColor)
    }

    // MARK: - Footer Subviews

    private var imageFooter: some View {
        HStack {
            Spacer()

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

    private var textFooter: some View {
        HStack {
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
        }
    }

    private var hexDumpFooter: some View {
        VStack(spacing: 10) {
            // Row 1: Theme selection and Copy Hex Button
            HStack(alignment: .center) {
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
                    let formattedText = generateEntireHexDump()
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(formattedText, forType: .string)
                }) {
                    Label("Copy Hex Dump", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            // Row 2: Chunk Extractor Controls
            HStack(alignment: .bottom) {
                HStack(spacing: 6) {
                    Image(systemName: "scissors")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Binary Chunk Extractor:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 6)
                
                Spacer()
                
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From Offset").font(.system(size: 9)).foregroundColor(.secondary)
                        TextField("0", text: $hexFromInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("To Offset").font(.system(size: 9)).foregroundColor(.secondary)
                        TextField("", text: $hexToInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chunk Filename").font(.system(size: 9)).foregroundColor(.secondary)
                        TextField("chunk.bin", text: $chunkFilename)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                    Button("EXTRACT CHUNK") {
                        saveBinaryChunk()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
    }



    // MARK: - Helper decoders & actions

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
        
        let isBin = isBinaryFile(data: targetData)
        if isBin {
            self.rawTextCache = "[BINARY EXE/DATA BLOCK – CHOOSE \"ASCII CLEANED\" OR \"FIND STRINGS (length >= 4)\" IN TEXT VIEWER OPTIONS TO EXTRACT EMBEDED TEXT PLAIN]"
        } else {
            self.rawTextCache = String(data: targetData, encoding: .utf8) ?? String(data: targetData, encoding: .isoLatin1) ?? "Undecodable text format."
        }
        
        self.asciiCleanedCache = asciiCleaned(data: targetData)
        self.findStringsCache = findStrings(data: targetData)
        
        updateDisplayedText()
    }
    
    private func updateDisplayedText() {
        switch textFormat {
        case .rawText:
            self.textContents = rawTextCache
        case .asciiCleaned:
            self.textContents = asciiCleanedCache
        case .findStrings:
            self.textContents = findStringsCache
        }
    }
    
    private func isBinaryFile(data: Data) -> Bool {
        if data.isEmpty { return false }
        let checkLimit = min(data.count, 8000)
        var controlCount = 0
        var hasNull = false
        
        for i in 0..<checkLimit {
            let byte = data[i]
            if byte == 0 {
                hasNull = true
                break
            }
            if byte < 32 && byte != 9 && byte != 10 && byte != 13 {
                controlCount += 1
            }
        }
        
        if hasNull {
            return true
        }
        
        let ratio = Double(controlCount) / Double(checkLimit)
        return ratio > 0.10
    }
    
    private func asciiCleaned(data: Data) -> String {
        var scalars = [UnicodeScalar]()
        scalars.reserveCapacity(data.count)
        
        for byte in data {
            if (byte >= 32 && byte <= 126) || byte == 9 || byte == 10 || byte == 13 {
                scalars.append(UnicodeScalar(byte))
            }
        }
        
        return String(String.UnicodeScalarView(scalars))
    }
    
    private func findStrings(data: Data, minLength: Int = 4) -> String {
        var result = ""
        result.reserveCapacity(data.count / 10)
        
        var currentScalars = [UnicodeScalar]()
        currentScalars.reserveCapacity(128)
        
        for byte in data {
            if byte >= 32 && byte <= 126 {
                currentScalars.append(UnicodeScalar(byte))
            } else {
                if currentScalars.count >= minLength {
                    result.append(String(String.UnicodeScalarView(currentScalars)))
                    result.append("\n")
                }
                currentScalars.removeAll(keepingCapacity: true)
            }
        }
        if currentScalars.count >= minLength {
            result.append(String(String.UnicodeScalarView(currentScalars)))
            result.append("\n")
        }
        
        return result
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

    private func saveBinaryChunk() {
        guard let fromVal = Int(hexFromInput), fromVal >= 0, fromVal < fileData.count else {
            self.errorMessage = "Invalid 'From' offset. Must be between 0 and \(fileData.count - 1)."
            self.showErrorAlert = true
            return
        }
        
        let toVal: Int
        if hexToInput.trimmingCharacters(in: .whitespaces).isEmpty {
            toVal = fileData.count
        } else if let val = Int(hexToInput), val > fromVal, val <= fileData.count {
            toVal = val
        } else {
            self.errorMessage = "Invalid 'To' offset. Must be between 'From' and \(fileData.count)."
            self.showErrorAlert = true
            return
        }
        
        let chunkData = fileData.subdata(in: fromVal..<toVal)
        SavePanel.showGenericSave(suggestedName: chunkFilename, title: "Save Binary Chunk") { url in
            guard let url = url else { return }
            do {
                try chunkData.write(to: url)
            } catch {
                self.errorMessage = "Failed to save chunk: \(error.localizedDescription)"
                self.showErrorAlert = true
            }
        }
    }

    private func generateEntireHexDump() -> String {
        var result = ""
        let count = fileData.count
        for index in 0..<Int(ceil(Double(count) / 16.0)) {
            let offset = index * 16
            
            var hexParts1 = ""
            var hexParts2 = ""
            for i in 0..<8 {
                if offset + i < count {
                    hexParts1 += String(format: "%02X ", fileData[offset + i])
                } else {
                    hexParts1 += "   "
                }
            }
            for i in 8..<16 {
                if offset + i < count {
                    hexParts2 += String(format: "%02X ", fileData[offset + i])
                } else {
                    hexParts2 += "   "
                }
            }
            var asciiChars = ""
            for i in 0..<16 {
                if offset + i < count {
                    let byte = fileData[offset + i]
                    if byte >= 32 && byte <= 126 {
                        asciiChars.append(Character(UnicodeScalar(byte)))
                    } else {
                        asciiChars.append(".")
                    }
                } else {
                    asciiChars.append(" ")
                }
            }
            let offsetStr = String(format: "%06X", offset)
            result += "\(offsetStr)  \(hexParts1) \(hexParts2) |\(asciiChars)|\n"
        }
        return result
    }
}

// MARK: - Supporting Hex & Marquee Views

struct HexDumpView: View {
    let data: Data
    let textColor: Color
    let backgroundColor: Color
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(0..<Int(ceil(Double(data.count) / 16.0)), id: \.self) { lineIndex in
                    Text(formatLine(index: lineIndex))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(textColor)
                }
            }
            .padding()
        }
        .background(backgroundColor)
    }
    
    private func formatLine(index: Int) -> String {
        let offset = index * 16
        let count = data.count
        
        var hexParts1 = ""
        var hexParts2 = ""
        
        for i in 0..<8 {
            if offset + i < count {
                hexParts1 += String(format: "%02X ", data[offset + i])
            } else {
                hexParts1 += "   "
            }
        }
        
        for i in 8..<16 {
            if offset + i < count {
                hexParts2 += String(format: "%02X ", data[offset + i])
            } else {
                hexParts2 += "   "
            }
        }
        
        var asciiChars = ""
        for i in 0..<16 {
            if offset + i < count {
                let byte = data[offset + i]
                if byte >= 32 && byte <= 126 {
                    asciiChars.append(Character(UnicodeScalar(byte)))
                } else {
                    asciiChars.append(".")
                }
            } else {
                asciiChars.append(" ")
            }
        }
        
        let offsetStr = String(format: "%06X", offset)
        return "\(offsetStr)  \(hexParts1) \(hexParts2) |\(asciiChars)|"
    }
}



// MARK: - Window Manager

final class AtariSTImageViewerWindowManager: NSObject, NSWindowDelegate {
    static let shared = AtariSTImageViewerWindowManager()
    
    private var window: NSWindow?
    private var contentController: NSHostingController<AtariSTImageViewerSheet>?
    
    func show(filename: String, fileData: Data, initialMode: ViewMode) {
        if let window = self.window {
            let sheetView = AtariSTImageViewerSheet(
                filename: filename,
                fileData: fileData,
                initialMode: initialMode
            )
            window.contentView = NSHostingView(rootView: sheetView)
            window.title = filename
            window.makeKeyAndOrderFront(nil)
        } else {
            let sheetView = AtariSTImageViewerSheet(
                filename: filename,
                fileData: fileData,
                initialMode: initialMode
            )
            let hostingController = NSHostingController(rootView: sheetView)
            self.contentController = hostingController
            
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 750, height: 550),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = filename
            win.contentViewController = hostingController
            win.minSize = NSSize(width: 600, height: 450)
            win.center()
            win.setFrameAutosaveName("AtariSTImageViewerWindow")
            win.isReleasedWhenClosed = false
            win.delegate = self
            
            self.window = win
            win.makeKeyAndOrderFront(nil)
        }
    }
    
    func close() {
        guard let win = self.window else { return }
        win.close()
        
        self.window = nil
        self.contentController = nil
        
        DispatchQueue.main.async {
            AppViewModel.shared.showViewer = false
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        self.window = nil
        self.contentController = nil
        
        DispatchQueue.main.async {
            AppViewModel.shared.showViewer = false
        }
    }
}
