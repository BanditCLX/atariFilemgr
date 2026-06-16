// DiskFileRowView.swift — AtariFileMgr
// Single row in the Atari ST disk image panel.
//
// Drag & Drop architecture:
//  - .onDrop(of:) instead of .dropDestination(for:) is used because
//    nested .dropDestination calls in LazyVStack on macOS
//    are unreliable — the outer container always "wins".
//    .onDrop() is based on NSItemProvider and works reliably.
//  - DiskEntryTransfer: custom type for intra-disk moves
 import SwiftUI
import UniformTypeIdentifiers

// MARK: - Transferable for Disk Entries (intra-disk Move & Extract)

struct DiskEntryTransfer: Codable, Transferable {
    let entryID: UUID
    let tempURL: URL

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .diskEntry)
        ProxyRepresentation(exporting: \.tempURL)
    }
}

extension UTType {
    static let diskEntry = UTType(exportedAs: "de.atari.filemgr.diskentry")
}

// MARK: - DiskFileRowView

struct DiskFileRowView: View {
    let entry: GEMDOSEntry
    let isSelected: Bool
    let compressionFormat: CompressionFormat?
    let onExtract: (() -> Void)?

    /// Called when macOS URLs are dropped onto this folder
    var onURLDrop: (([URL]) -> Void)?
    /// Called when another disk entry is dragged onto this folder
    var onEntryDrop: ((UUID) -> Void)?

    @State private var isURLTargeted   = false
    @State private var isEntryTargeted = false
    @State private var showCompressionPopover = false

    private var isAnyTarget: Bool { isURLTargeted || isEntryTargeted }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .frame(width: 16)
                .foregroundStyle(iconColor)

            HStack(spacing: 6) {
                Text(entry.displayName)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                
                if let format = compressionFormat {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .help(format.name)
                        .onTapGesture {
                            showCompressionPopover = true
                        }
                        .onHover { hovering in
                            showCompressionPopover = hovering
                        }
                        .popover(isPresented: $showCompressionPopover, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(format.name)
                                    .font(.system(size: 12, weight: .bold))
                                
                                if !format.filesInside.isEmpty {
                                    Text("Archive contains:")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 2) {
                                            ForEach(format.filesInside, id: \.self) { file in
                                                Text("• \(file)")
                                                    .font(.system(size: 10, design: .monospaced))
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 120)
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    showCompressionPopover = false
                                    onExtract?()
                                }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.down")
                                        Text(format.name.contains("Pack-Ice") ? "Extract File..." : "Download File...")
                                    }
                                    .font(.system(size: 11))
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(10)
                            .frame(width: 220)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(attrString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 38)

            Text(entry.sizeString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)

            Text(entry.dateString)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(rowBackground)
        // ── Drop: macOS files via NSItemProvider (more reliable than .dropDestination) ──
        .onDrop(of: [.fileURL, .url], isTargeted: entry.isDirectory ? $isURLTargeted : .constant(false)) { providers in
            guard entry.isDirectory, let onURLDrop else { return false }
            loadURLs(from: providers) { urls in
                guard !urls.isEmpty else { return }
                onURLDrop(urls)
            }
            return true
        }
        // ── Drop: another disk entry onto this folder ──
        .onDrop(of: [.diskEntry], isTargeted: entry.isDirectory ? $isEntryTargeted : .constant(false)) { providers in
            guard entry.isDirectory, let onEntryDrop else { return false }
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.diskEntry.identifier) { data, _ in
                    guard let data,
                          let transfer = try? JSONDecoder().decode(DiskEntryTransfer.self, from: data)
                    else { return }
                    DispatchQueue.main.async { onEntryDrop(transfer.entryID) }
                }
            }
            return true
        }
        // ── Visual focus indicator ──
        .overlay(
            isAnyTarget
            ? RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(.horizontal, 2)
            : nil
        )
    }

    // MARK: - Extract URL from NSItemProvider

    private func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            // First try public.file-url
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    } else if let url = item as? URL {
                        urls.append(url)
                    } else if let str = item as? String, let url = URL(string: str) {
                        urls.append(url)
                    }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    defer { group.leave() }
                    if let url { urls.append(url) }
                }
            }
        }

        group.notify(queue: .main) { completion(urls) }
    }

    // MARK: - Helpers

    private var iconName: String {
        if entry.isDirectory { return "folder.fill" }
        switch entry.name83.ext.lowercased() {
        case "prg", "tos", "ttp", "acc": return "cpu"
        case "txt", "nfo", "doc":        return "doc.text"
        case "neo", "pi1", "pi2", "pi3",
             "pc1", "pc2", "pc3":        return "photo"
        case "mod", "snd", "ym":         return "waveform"
        case "arc", "zip", "lzh":        return "archivebox"
        case "bas":                       return "terminal"
        default:                          return "doc"
        }
    }

    private var iconColor: Color { entry.isDirectory ? .yellow : .cyan }

    private var attrString: String {
        let a = entry.attributes
        return [
            a.contains(.readOnly) ? "R" : "-",
            a.contains(.hidden)   ? "H" : "-",
            a.contains(.system)   ? "S" : "-",
            a.contains(.archive)  ? "A" : "-",
        ].joined()
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isAnyTarget {
            Color.accentColor.opacity(0.15)
        } else if isSelected {
            Color.accentColor.opacity(0.2)
        } else {
            Color.clear
        }
    }
}
