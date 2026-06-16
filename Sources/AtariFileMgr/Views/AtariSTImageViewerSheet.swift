// AtariSTImageViewerSheet.swift — AtariFileMgr
// SwiftUI preview modal for retro Atari ST graphic files.

import SwiftUI

struct AtariSTImageViewerSheet: View {
    @Binding var isPresented: Bool
    let filename: String
    let fileData: Data

    @State private var decodedImage: DecodedAtariSTImage? = nil
    @State private var zoomScale: CGFloat = 2.0
    @State private var isFitToWindow: Bool = true
    @State private var hasFailed = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    if let img = decodedImage {
                        Text("\(img.formatName)  •  \(img.resolutionText)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else if hasFailed {
                        Text("Supported formats: DEGAS, NEOchrome, STAD, Spectrum 512 SPU")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    } else {
                        Text("Decoding bitplanes...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { isPresented = false }) {
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
                    .background(ImageGridBackground())
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
            HStack(alignment: .bottom) {
                // Palette list
                if let decoded = decodedImage, !decoded.palette.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Palette Colors")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 3) {
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

                // Display options
                if decodedImage != nil {
                    VStack(alignment: .trailing, spacing: 6) {
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
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 24, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 420)
        .onAppear {
            decodeImageFile()
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
