// PhysicalLayoutInfoPane.swift — AtariFileMgr
// Pane on the right: displays boot sector info, cluster allocation map, and boot sector controls.

import SwiftUI

struct PhysicalLayoutInfoPane: View {
    @ObservedObject var vm: DiskPaneViewModel
    @EnvironmentObject var appVM: AppViewModel

    @State private var oemIDInput: String = ""

    private var fs: GEMDOSFilesystem? { appVM.filesystem }

    var body: some View {
        VStack(spacing: 0) {
            if let fs = fs {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // OEM ID Section
                        oemIDSection(fs: fs)
                        
                        Divider()

                        // Disk parameters
                        diskParametersSection(fs: fs)

                        Divider()

                        // Space Utilized Section
                        spaceUtilizedSection(fs: fs)

                        Divider()

                        // Cluster Allocation Map
                        clusterMapSection(fs: fs)
                    }
                    .padding()
                }
            } else {
                emptyState
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if let fs = fs {
                oemIDInput = fs.bootSector.oemName.trimmingCharacters(in: .whitespaces)
            }
        }
        .onChange(of: appVM.filesystem?.bootSector.oemName) { newName in
            if let name = newName {
                oemIDInput = name.trimmingCharacters(in: .whitespaces)
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack {
            Spacer()
            Image(systemName: "info.circle")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
            Text("No disk loaded")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func oemIDSection(fs: GEMDOSFilesystem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OEM ID")
                .font(.headline)
            HStack(spacing: 8) {
                Text("=")
                    .font(.system(.body, design: .monospaced))
                TextField("", text: $oemIDInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onChange(of: oemIDInput) { newValue in
                        oemIDInput = String(newValue.prefix(8))
                    }
                
                Button("SET") {
                    vm.setOEMName(oemIDInput)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func diskParametersSection(fs: GEMDOSFilesystem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IMAGE:")
                .font(.caption).bold().foregroundStyle(.secondary)
            Text(appVM.diskSourceURL?.lastPathComponent ?? "New Disk")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BPB LOGICAL CAP:").font(.caption2).foregroundStyle(.secondary)
                        Text(formatBytes(fs.bootSector.totalSectors * 512)).font(.system(size: 11, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PHYSICAL BUFFER:").font(.caption2).foregroundStyle(.secondary)
                        Text(formatBytes(fs.totalBytes)).font(.system(size: 11, design: .monospaced))
                    }
                }
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SECT/CLUS:").font(.caption2).foregroundStyle(.secondary)
                        Text("\(fs.bootSector.sectorsPerCluster)").font(.system(size: 11, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BYTES/SECT:").font(.caption2).foregroundStyle(.secondary)
                        Text("\(fs.bootSector.bytesPerSector)").font(.system(size: 11, design: .monospaced))
                    }
                }
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SECT/FAT:").font(.caption2).foregroundStyle(.secondary)
                        Text("\(fs.bootSector.sectorsPerFAT)").font(.system(size: 11, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FAT COPIES:").font(.caption2).foregroundStyle(.secondary)
                        Text("\(fs.bootSector.fatCount)").font(.system(size: 11, design: .monospaced))
                    }
                }
                if let geo = appVM.openDiskImage?.geometry {
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TRACKS:").font(.caption2).foregroundStyle(.secondary)
                            Text("\(geo.tracks)").font(.system(size: 11, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SIDES:").font(.caption2).foregroundStyle(.secondary)
                            Text("\(geo.sides)").font(.system(size: 11, design: .monospaced))
                        }
                    }
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SECTORS/TRACK:").font(.caption2).foregroundStyle(.secondary)
                            Text("\(geo.sectorsPerTrack)").font(.system(size: 11, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TOTAL SECTORS:").font(.caption2).foregroundStyle(.secondary)
                            Text("\(geo.totalSectors)").font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            Divider()

            Text("CODE FOUND: \(fs.bootSector.hasBootCode ? "YES" : "NO"), BOOTABLE: \(fs.bootSector.isBootable ? "YES" : "NO")")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.vertical, 2)
            
            HStack(spacing: 8) {
                Button("MAKE BOOTABLE") {
                    vm.makeBootable()
                }
                .buttonStyle(.bordered)
                .disabled(fs.bootSector.isBootable)
                
                Button("VIEW BOOT") {
                    appVM.viewHex(name: "BOOTSECTOR.BIN", data: fs.bootSector.rawData)
                }
                .buttonStyle(.bordered)

                Button("BOOT DISK") {
                    vm.installStandardBootCode()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func spaceUtilizedSection(fs: GEMDOSFilesystem) -> some View {
        let total = fs.bootSector.clusterCount
        let free = fs.freeBytes / fs.clusterSize
        let used = total - free
        let percentage = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0.0

        let clusterSizeKB = fs.clusterSize / 1024
        let usedKB = used * clusterSizeKB
        let totalKB = total * clusterSizeKB
        let freeKB = free * clusterSizeKB

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Floppy Space Utilized:")
                    .font(.caption).bold()
                Spacer()
                Text(String(format: "%.1f%%", percentage))
                    .font(.caption).bold()
            }

            ProgressView(value: percentage, total: 100.0)
                .progressViewStyle(.linear)

            HStack {
                Text("\(used) / \(total) clusters used (\(usedKB) KB / \(totalKB) KB)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(free) Free (\(freeKB) KB)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func clusterMapSection(fs: GEMDOSFilesystem) -> some View {
        ClusterAllocationMapView(
            totalClusters: Int(fs.bootSector.clusterCount),
            selectedEntryClusters: vm.selectedEntryClusters,
            fs: fs,
            onHoverCluster: { cluster, isHovering in
                if isHovering {
                    if let result = vm.findEntry(forCluster: cluster) {
                        vm.hoveredEntry = result.entry
                    } else {
                        vm.hoveredEntry = nil
                    }
                } else {
                    vm.hoveredEntry = nil
                }
            },
            onTapCluster: { cluster in
                vm.openClusterFileInHexEditor(cluster: cluster)
            },
            hoverTextProvider: { cluster in
                let fatVal = fs.getFatEntry(for: cluster)
                if fatVal == 0x000 {
                    return "Clust \(cluster): Free"
                } else if fatVal == 0xFF7 {
                    return "Clust \(cluster): Bad"
                }
                if let result = vm.findEntry(forCluster: cluster) {
                    let status = result.isDeleted ? "Deleted" : (result.entry.isDirectory ? "Directory" : "Allocated")
                    let sizeStr = result.entry.isDirectory ? "" : " (\(result.entry.sizeString))"
                    return "Clust \(cluster): \(result.entry.displayName)\(sizeStr) · \(status)"
                }
                return "Clust \(cluster): Allocated"
            },
            clustersForClusterOwner: { cluster in
                if let result = vm.findEntry(forCluster: cluster) {
                    let chain = fs.getClusterChain(for: result.entry, isDeleted: result.isDeleted)
                    return Set(chain)
                }
                return []
            }
        ).equatable()
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    }

    private func formatBytes<T: BinaryInteger>(_ bytes: T) -> String {
        formatBytes(Int(bytes))
    }
}

// MARK: - ClusterAllocationMapView

struct ClusterAllocationMapView: View, Equatable {
    let totalClusters: Int
    let selectedEntryClusters: Set<UInt16>
    let fs: GEMDOSFilesystem
    let onHoverCluster: (UInt16, Bool) -> Void
    let onTapCluster: (UInt16) -> Void
    let hoverTextProvider: (UInt16) -> String
    let clustersForClusterOwner: (UInt16) -> Set<UInt16>

    @State private var hoveredCluster: Int? = nil

    static func == (lhs: ClusterAllocationMapView, rhs: ClusterAllocationMapView) -> Bool {
        return lhs.totalClusters == rhs.totalClusters &&
               lhs.selectedEntryClusters == rhs.selectedEntryClusters &&
               lhs.fs === rhs.fs
    }

    var body: some View {
        let hoveredChain: Set<UInt16> = {
            guard let hc = hoveredCluster else { return [] }
            return clustersForClusterOwner(UInt16(hc))
        }()
        
        return VStack(alignment: .leading, spacing: 2) {
            Text("CLUSTER ALLOCATION MAP")
                .font(.caption).bold()
            
            Text(hoverText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 16, alignment: .leading)
                .padding(.bottom, 6)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 36)
            
            LazyVGrid(columns: columns, spacing: 1.5) {
                ForEach(0..<totalClusters, id: \.self) { index in
                    let cluster = UInt16(index + 2)
                    let fatVal = fs.getFatEntry(for: cluster)
                    let isFree = fatVal == 0x000
                    let isBad = fatVal == 0xFF7
                    let isSelected = selectedEntryClusters.contains(cluster)
                    let isHoveredOwner = hoveredChain.contains(cluster)
                    let isHighlighted = isSelected || isHoveredOwner
                    
                    let cellColor: Color = {
                        if isHighlighted { return Color.accentColor }
                        if isBad { return Color.red }
                        if isFree { return Color.gray.opacity(0.12) }
                        return Color.gray.opacity(0.55)
                    }()
                    
                    let strokeColor: Color = {
                        if isHighlighted { return Color.accentColor }
                        if isBad { return Color.red }
                        return Color(NSColor.textColor).opacity(0.18)
                    }()
                    
                    RoundedRectangle(cornerRadius: 1.0)
                        .fill(cellColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.0)
                                .stroke(strokeColor, lineWidth: isHighlighted ? 0.8 : 0.4)
                        )
                        .frame(height: 6)
                        .onHover { isHovering in
                            if isHovering {
                                hoveredCluster = Int(cluster)
                            } else {
                                if hoveredCluster == Int(cluster) {
                                    hoveredCluster = nil
                                }
                            }
                            onHoverCluster(cluster, isHovering)
                        }
                        .onTapGesture {
                            onTapCluster(cluster)
                        }
                }
            }
            .id(selectedEntryClusters) // Forces immediate redraw when selection changes
        }
    }

    private var hoverText: String {
        guard let clusterNum = hoveredCluster else { return "Hover cell" }
        return hoverTextProvider(UInt16(clusterNum))
    }
}
