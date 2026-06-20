// DeletedFilesSheetView.swift — AtariFileMgr
// Sheet for displaying and recovering deleted files from the disk image.

import SwiftUI

struct DeletedFilesSheetView: View {
    @ObservedObject var vm: DiskPaneViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "trash.slash.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recover Deleted Files")
                        .font(.title2).fontWeight(.semibold)
                    Text("The following files were found in the directory entries of the disk. Since the FAT table is cleared upon deletion, recovery assumes contiguous sectors starting from the first cluster.")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 16)

            Divider()

            // File List
            VStack(spacing: 0) {
                // Table header
                HStack(spacing: 0) {
                    Text("Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)
                    
                    Divider().frame(height: 16)
                    
                    Text("Original Path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    
                    Divider().frame(height: 16)
                    
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                        .padding(.horizontal, 8)
                    
                    Divider().frame(height: 16)
                    
                    Text("Start Cluster")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .center)
                        .padding(.horizontal, 8)
                    
                    Divider().frame(height: 16)
                    
                    Text("Date Modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                        .padding(.horizontal, 8)
                    
                    Divider().frame(height: 16)
                    
                    Text("Action")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .center)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                if vm.isScanningDeleted {
                    VStack {
                        Spacer()
                        ProgressView("Scanning directory tree...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.deletedFiles.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "trash.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 8)
                        Text("No deleted files found")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.deletedFiles, id: \.entry.id) { path, entry in
                                HStack(spacing: 0) {
                                    // Icon and Name
                                    HStack(spacing: 6) {
                                        Image(systemName: fileIcon(for: entry.name83.ext))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.cyan)
                                            .frame(width: 16)
                                        Text(entry.displayName)
                                            .font(.system(size: 11, design: .monospaced))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 140, alignment: .leading)

                                    // Path
                                    Text(path)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .lineLimit(1)

                                    // Size
                                    Text(entry.sizeString)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .trailing)
                                        .padding(.horizontal, 8)

                                    // Start Cluster
                                    Text("\(entry.startCluster)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .center)
                                        .padding(.horizontal, 8)

                                    // Date
                                    Text(entry.dateString)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 110, alignment: .leading)
                                        .padding(.horizontal, 8)

                                    // Action
                                    Button {
                                        vm.recoverFile(entry, suggestedName: entry.displayName)
                                    } label: {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.blue)
                                    .frame(width: 60, alignment: .center)
                                    .help("Recover and Download File")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.clear)
                                
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .border(Color(NSColor.separatorColor))
            .background(Color(NSColor.textBackgroundColor))
            .frame(height: 300)
            .padding(.bottom, 16)

            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 720, height: 430)
        .onAppear {
            vm.scanForDeletedFiles()
        }
    }

    private func fileIcon(for ext: String) -> String {
        switch ext.lowercased() {
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
}
