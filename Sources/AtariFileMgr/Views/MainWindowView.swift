// MainWindowView.swift — AtariFileMgr
// Root view: full application layout with toolbar, dual-pane file manager,
// bottom action bar, and status bar.

import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject var appVM: AppViewModel
    @StateObject private var localVM  = LocalPaneViewModel()
    @StateObject private var diskVM   = DiskPaneViewModel(appViewModel: AppViewModel.shared)

    // Dialogs
    @State private var showNewDisk     = false
    @State private var showProperties  = false
    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 0) {
            // ── Main toolbar ──────────────────────────────────────────────
            mainToolbar

            Divider()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    // ── Pane headers (labels) ──────────────────────────────────────
                    paneHeaders(totalWidth: geo.size.width)

                    Divider()

                    // ── Dual panes ────────────────────────────────────────────────
                    HStack(spacing: 0) {
                        LocalPaneView(vm: localVM, diskPaneVM: diskVM)
                            .frame(width: geo.size.width * splitFraction)

                        dividerHandle(in: geo)

                        DiskPaneView(vm: diskVM, localVM: localVM)
                            .frame(maxWidth: .infinity)
                    }
                    .coordinateSpace(name: "splitContainer")
                    .frame(maxHeight: .infinity)
                }
            }

            // ── Status bar ────────────────────────────────────────────────
            Divider()
            statusBar
        }
        .background(WindowAccessor())
        .sheet(isPresented: $showNewDisk)   { NewDiskSheetView(isPresented: $showNewDisk).environmentObject(appVM) }
        .sheet(isPresented: $showProperties) { propertiesSheet }
        .onChange(of: appVM.showViewer) { show in
            if show, let name = appVM.viewerImageName, let data = appVM.viewerImageData {
                AtariSTImageViewerWindowManager.shared.show(filename: name, fileData: data)
            } else if !show {
                AtariSTImageViewerWindowManager.shared.close()
            }
        }
        .alert("Error", isPresented: $appVM.showError) {
            Button("OK") { appVM.showError = false }
        } message: {
            Text(appVM.errorMessage ?? "An unknown error occurred.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNewDisk))  { _ in
            Task {
                if await appVM.checkDiscardChanges() {
                    showNewDisk = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOpenDisk)) { _ in
            Task {
                if await appVM.checkDiscardChanges() {
                    openDisk()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSaveAs))   { _ in saveAs() }
        .onReceive(NotificationCenter.default.publisher(for: .diskLoaded))   { _ in diskVM.navigateToRoot() }
    }

    // MARK: - Main toolbar

    private var mainToolbar: some View {
        HStack(spacing: 6) {
            // App identity
            HStack(spacing: 6) {
                if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") ??
                             Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                }
                Text("AtariFileMgr")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.trailing, 8)

            Divider().frame(height: 20)

            // New
            ToolbarButton(icon: "plus.square", label: "New") {
                Task {
                    if await appVM.checkDiscardChanges() {
                        showNewDisk = true
                    }
                }
            }

            // Open
            ToolbarButton(icon: "folder", label: "Open") {
                Task {
                    if await appVM.checkDiscardChanges() {
                        openDisk()
                    }
                }
            }

            // Save / Save As
            ToolbarButton(icon: "square.and.arrow.down", label: "Save") {
                if appVM.diskSourceURL != nil { appVM.save() }
                else { saveAs() }
            }
            .disabled(appVM.openDiskImage == nil)

            ToolbarButton(icon: "square.and.arrow.down.on.square", label: "Save As") {
                saveAs()
            }
            .disabled(appVM.openDiskImage == nil)



            Spacer()

            // Recent files
            if !appVM.recentFiles.isEmpty {
                Menu {
                    ForEach(appVM.recentFiles, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            appVM.openDisk(url: url)
                        }
                    }
                } label: {
                    Label("Recent", systemImage: "clock")
                        .font(.system(size: 12))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }

            // Dirty indicator
            if appVM.isDirty {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 8))
                    .help("Unsaved changes")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - Pane headers

    private func paneHeaders(totalWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.secondary)
                Text("Local macOS Filesystem")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(width: totalWidth * splitFraction, alignment: .leading)

            Divider().frame(width: 5, height: 16)

            HStack {
                Image(systemName: "opticaldisc")
                    .foregroundStyle(.secondary)
                Text(headerTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var headerTitle: String {
        if let url = appVM.diskSourceURL {
            return url.lastPathComponent + (appVM.isDirty ? " ●" : "")
        }
        return "Atari ST Disk Image"
    }

    // MARK: - Divider handle (resizable pane split)

    private func dividerHandle(in geo: GeometryProxy) -> some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 5)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            )
            .gesture(
                DragGesture(coordinateSpace: .named("splitContainer"))
                    .onChanged { value in
                        let newFraction = value.location.x / geo.size.width
                        splitFraction = max(0.25, min(0.75, newFraction))
                    }
            )
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }



    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            // Left pane status
            Label {
                Text(localVM.currentURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 12)

            // Right pane status
            Label {
                Text(diskVM.diskInfoString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 12)

            // Branding
            Text("v1.5 · coded by Bandit CLiMATiCS")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .opacity(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Properties sheet

    private var propertiesSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disk Properties")
                .font(.title2).fontWeight(.semibold)
            Divider()
            if let img = appVM.openDiskImage, let fs = appVM.filesystem {
                let geo = img.geometry
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { Text("Format:").foregroundStyle(.secondary); Text(img.formatName) }
                    GridRow { Text("Geometry:").foregroundStyle(.secondary); Text(geo.description) }
                    GridRow { Text("Total:").foregroundStyle(.secondary); Text("\(geo.totalBytes / 1024) KB") }
                    GridRow { Text("Free:").foregroundStyle(.secondary); Text("\(fs.freeBytes / 1024) KB") }
                    GridRow { Text("Used:").foregroundStyle(.secondary); Text("\(fs.usedBytes / 1024) KB") }
                    GridRow { Text("Cluster:").foregroundStyle(.secondary); Text("\(fs.clusterSize) bytes") }
                }
            }
            Spacer()
            Button("Close") { showProperties = false }
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 320, height: 280)
    }

    // MARK: - Copy/Move helpers

    private var canCopyOrMove: Bool {
        // Can copy from Mac → Disk or Disk → Mac
        !localVM.selectedItems.isEmpty || !diskVM.selectedEntries.isEmpty
    }

    private func copySelection() {
        let localSelected = localVM.selectedItems
        let diskSelected  = diskVM.selectedEntries
        let destMacDir    = localVM.currentURL
        
        Task {
            diskVM.isLoading = true
            // Mac → Disk
            for item in localSelected {
                do {
                    try await diskVM.importFile(url: item.url)
                } catch {
                    diskVM.errorMessage = error.localizedDescription
                }
            }
            // Disk → Mac
            for entry in diskSelected {
                do {
                    try await diskVM.extractEntry(entry, to: destMacDir)
                } catch {
                    diskVM.errorMessage = error.localizedDescription
                }
            }
            diskVM.refresh()
            localVM.refresh()
            diskVM.isLoading = false
        }
    }

    private func moveSelection() {
        let localSelected = localVM.selectedItems
        let diskSelected  = diskVM.selectedEntries
        let destMacDir    = localVM.currentURL
        
        Task {
            diskVM.isLoading = true
            // Mac → Disk (Move)
            for item in localSelected {
                do {
                    try await diskVM.importFile(url: item.url)
                    // Since it's a move, delete from macOS side (simulate)
                    try? FileManager.default.removeItem(at: item.url)
                } catch {
                    diskVM.errorMessage = error.localizedDescription
                }
            }
            // Disk → Mac (Move)
            for entry in diskSelected {
                do {
                    try await diskVM.extractEntry(entry, to: destMacDir)
                    try appVM.filesystem?.delete(entry)
                    appVM.isDirty = true
                } catch {
                    diskVM.errorMessage = error.localizedDescription
                }
            }
            diskVM.refresh()
            localVM.refresh()
            diskVM.isLoading = false
        }
    }

    // MARK: - Open / Save helpers

    /// Opens NSOpenPanel and loads the selected disk image.
    private func openDisk() {
        OpenPanel.show { url in
            guard let url else { return }
            appVM.openDisk(url: url)
        }
    }

    /// Opens NSSavePanel and saves the current image under a new path.
    private func saveAs() {
        guard appVM.openDiskImage != nil else { return }
        let suggestedName = appVM.diskSourceURL?.lastPathComponent ?? "NewDisk.st"
        SavePanel.show(suggestedName: suggestedName) { url in
            guard let url else { return }
            appVM.saveAs(url: url)
        }
    }
}

// MARK: - ToolbarButton

struct ToolbarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(label)
    }
}


