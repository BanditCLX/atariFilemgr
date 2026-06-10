// NewDiskSheetView.swift — AtariFileMgr
// Sheet for creating a new blank Atari ST disk image.

import SwiftUI

enum CreationFormat: Hashable, Identifiable {
    case preset(DiskFormat)
    case custom

    var id: String {
        switch self {
        case .preset(let fmt): return fmt.rawValue
        case .custom:          return "Custom"
        }
    }
}

struct NewDiskSheetView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Binding var isPresented: Bool

    @State private var selectedOption: CreationFormat = .preset(.ds_dd_9)
    @State private var customTracks: Int = 80
    @State private var customSides: Int = 2
    @State private var customSectors: Int = 9
    @State private var volumeName: String = "ATARI"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Disk Image")
                        .font(.title2).fontWeight(.semibold)
                    Text("Create a blank, formatted Atari ST floppy disk")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 20)

            // Format picker
            VStack(alignment: .leading, spacing: 12) {
                Text("Disk Format").font(.headline)
                
                // Radio button list
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(DiskFormat.allCases) { fmt in
                        HStack(spacing: 8) {
                            Image(systemName: isSelected(fmt) ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(isSelected(fmt) ? .blue : .secondary)
                                .font(.system(size: 14))
                            Text(fmt.rawValue)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedOption = .preset(fmt)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: selectedOption == .custom ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedOption == .custom ? .blue : .secondary)
                            .font(.system(size: 14))
                        Text("Custom...")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedOption = .custom
                    }
                }
                .padding(.leading, 4)

                // Geometry info or custom stepper inputs
                if case .custom = selectedOption {
                    HStack(spacing: 16) {
                        // Tracks
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tracks").font(.caption2).foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                TextField("", value: $customTracks, format: .number)
                                    .frame(width: 50)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.center)
                                Stepper("", value: $customTracks, in: 70...90)
                                    .labelsHidden()
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                        // Sides
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sides").font(.caption2).foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                TextField("", value: $customSides, format: .number)
                                    .frame(width: 50)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.center)
                                Stepper("", value: $customSides, in: 1...2)
                                    .labelsHidden()
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                        // Sectors
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sectors").font(.caption2).foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                TextField("", value: $customSectors, format: .number)
                                    .frame(width: 50)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.center)
                                Stepper("", value: $customSectors, in: 8...27)
                                    .labelsHidden()
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                        // Capacity
                        let customCapacityBytes = customTracks * customSides * customSectors * 512
                        InfoBadge(label: "Capacity", value: "\(customCapacityBytes / 1024) KB")
                    }
                    .padding(.top, 4)
                } else if case .preset(let fmt) = selectedOption {
                    let geo = fmt.geometry
                    HStack(spacing: 16) {
                        InfoBadge(label: "Tracks",   value: "\(geo.tracks)")
                        InfoBadge(label: "Sides",    value: "\(geo.sides)")
                        InfoBadge(label: "Sectors",  value: "\(geo.sectorsPerTrack)/track")
                        InfoBadge(label: "Capacity", value: "\(geo.totalBytes / 1024) KB")
                    }
                    .padding(.top, 4)
                }
            }

            Divider().padding(.vertical, 16)

            // Volume name
            VStack(alignment: .leading, spacing: 6) {
                Text("Volume Name").font(.headline)
                TextField("ATARI", text: $volumeName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: volumeName) { newValue in
                        volumeName = String(newValue.uppercased().prefix(11))
                    }
                Text("Up to 11 characters, displayed as disk label")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    switch selectedOption {
                    case .preset(let format):
                        appVM.newDisk(format: format, volumeName: volumeName)
                    case .custom:
                        let geo = DiskGeometry(tracks: customTracks, sides: customSides, sectorsPerTrack: customSectors)
                        appVM.newDisk(geometry: geo, volumeName: volumeName)
                    }
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onChange(of: customTracks) { newValue in
            customTracks = max(70, min(90, newValue))
        }
        .onChange(of: customSides) { newValue in
            customSides = max(1, min(2, newValue))
        }
        .onChange(of: customSectors) { newValue in
            customSectors = max(8, min(27, newValue))
        }
    }

    private func isSelected(_ preset: DiskFormat) -> Bool {
        if case .preset(let current) = selectedOption {
            return current == preset
        }
        return false
    }
}

// MARK: - InfoBadge

private struct InfoBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced)).fontWeight(.semibold)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
