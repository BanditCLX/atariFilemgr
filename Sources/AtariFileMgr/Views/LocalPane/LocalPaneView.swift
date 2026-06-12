// LocalPaneView.swift — AtariFileMgr
// Left pane: browsing the local macOS filesystem with sidebar and file list.

import SwiftUI
import UniformTypeIdentifiers

struct LocalPaneView: View {
    @ObservedObject var vm: LocalPaneViewModel
    @ObservedObject var diskPaneVM: DiskPaneViewModel
    @EnvironmentObject var appVM: AppViewModel

    @State private var renameTarget: LocalItem?
    @State private var newName: String = ""
    @State private var showRenameAlert = false
    @State private var dragOver = false

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            navigationBar

            Divider()

            // Content: sidebar + file list
            HStack(spacing: 0) {
                sidebar
                Divider()
                fileList
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button(action: vm.goBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 20, height: 20)
            }
            .disabled(!vm.canGoBack)
            .buttonStyle(.plain)

            Button(action: vm.goForward) {
                Image(systemName: "chevron.right")
                    .frame(width: 20, height: 20)
            }
            .disabled(!vm.canGoForward)
            .buttonStyle(.plain)

            Button(action: vm.goUp) {
                Image(systemName: "arrow.up")
                    .frame(width: 20, height: 20)
            }
            .disabled(vm.currentURL.path == "/")
            .buttonStyle(.plain)

            Divider().frame(height: 14)

            // Path display
            Text(vm.currentURL.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: vm.refresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.bar)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSection(title: "FAVORITES") {
                ForEach(vm.favourites, id: \.url) { item in
                    SidebarRow(
                        icon: sidebarIcon(for: item.name),
                        label: item.name,
                        isSelected: vm.currentURL == item.url
                    ) {
                        vm.navigateTo(item.url)
                    }
                }
            }

            Divider()

            SidebarSection(title: "VOLUMES") {
                ForEach(vm.sidebarVolumes) { vol in
                    SidebarRow(
                        icon: "externaldrive.fill",
                        label: vol.name.isEmpty ? "Macintosh HD" : vol.name,
                        isSelected: vm.currentURL.path.hasPrefix(vol.url.path)
                    ) {
                        vm.navigateTo(vol.url)
                    }
                }
            }
        }
        .frame(width: 140)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - File list

    private var fileList: some View {
        VStack(spacing: 0) {
            // Column headers
            columnHeaders

            Divider()

            // File rows
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.items.isEmpty {
                Text("Empty folder")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.items) { item in
                            let isSelected = vm.selectedItems.contains(item)
                            LocalFileRowView(
                                item: item,
                                isSelected: isSelected
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let flags = NSEvent.modifierFlags
                                if flags.contains(.command) {
                                    if vm.selectedItems.contains(item) {
                                        vm.selectedItems.remove(item)
                                    } else {
                                        vm.selectedItems.insert(item)
                                    }
                                } else if flags.contains(.shift), let last = vm.selectedItems.first {
                                    if let lastIdx = vm.items.firstIndex(of: last),
                                       let curIdx = vm.items.firstIndex(of: item) {
                                        let start = min(lastIdx, curIdx)
                                        let end = max(lastIdx, curIdx)
                                        vm.selectedItems = Set(vm.items[start...end])
                                    }
                                } else {
                                    vm.selectedItems = [item]
                                }
                            }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    if item.isDirectory { vm.navigateTo(item.url) }
                                }
                            )
                            .draggable(item.url) {
                                Label(
                                    vm.selectedItems.contains(item) && vm.selectedItems.count > 1
                                    ? "\(vm.selectedItems.count) files"
                                    : item.name,
                                    systemImage: item.systemImage
                                )
                                .padding(6)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .contextMenu {
                                Button {
                                    let targets = vm.selectedItems.contains(item) ? vm.selectedItems : [item]
                                    Task {
                                        diskPaneVM.isLoading = true
                                        for target in targets {
                                            do {
                                                try await diskPaneVM.importFile(url: target.url)
                                            } catch {
                                                diskPaneVM.errorMessage = error.localizedDescription
                                            }
                                        }
                                        diskPaneVM.refresh()
                                        diskPaneVM.isLoading = false
                                    }
                                } label: {
                                    Label("Copy to Right", systemImage: "arrow.right.doc.on.doc")
                                }
                                .disabled(appVM.openDiskImage == nil)

                                Button {
                                    let targets = vm.selectedItems.contains(item) ? vm.selectedItems : [item]
                                    Task {
                                        diskPaneVM.isLoading = true
                                        for target in targets {
                                            do {
                                                try await diskPaneVM.importFile(url: target.url)
                                                try? FileManager.default.removeItem(at: target.url)
                                            } catch {
                                                diskPaneVM.errorMessage = error.localizedDescription
                                            }
                                        }
                                        diskPaneVM.refresh()
                                        vm.refresh()
                                        diskPaneVM.isLoading = false
                                    }
                                } label: {
                                    Label("Move to Right", systemImage: "arrow.right")
                                }
                                .disabled(appVM.openDiskImage == nil)

                                Divider()

                                Button {
                                    TextInputDialog.show(
                                        title: "Rename",
                                        placeholder: item.name,
                                        defaultValue: item.name,
                                        confirmLabel: "Rename"
                                    ) { newName in
                                        guard let newName, !newName.isEmpty else { return }
                                        let parent = item.url.deletingLastPathComponent()
                                        let dest = parent.appendingPathComponent(newName)
                                        do {
                                            try FileManager.default.moveItem(at: item.url, to: dest)
                                            vm.refresh()
                                        } catch {
                                            appVM.presentError(error)
                                        }
                                    }
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    let targets = vm.selectedItems.contains(item) ? vm.selectedItems : [item]
                                    for target in targets {
                                        do {
                                            try FileManager.default.removeItem(at: target.url)
                                        } catch {
                                            appVM.presentError(error)
                                        }
                                    }
                                    vm.refresh()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if !isSelected {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let destDir = vm.currentURL
            Task {
                let isFromDiskSelection = urls.contains { url in
                    url.path.contains(NSTemporaryDirectory()) &&
                    diskPaneVM.selectedEntries.contains { $0.displayName == url.lastPathComponent }
                }
                
                if isFromDiskSelection && !diskPaneVM.selectedEntries.isEmpty {
                    diskPaneVM.isLoading = true
                    for entry in diskPaneVM.selectedEntries {
                        do {
                            try await diskPaneVM.extractEntry(entry, to: destDir)
                        } catch {
                            appVM.presentError(error)
                        }
                    }
                    diskPaneVM.isLoading = false
                } else {
                    for url in urls {
                        let dest = destDir.appendingPathComponent(url.lastPathComponent)
                        if FileManager.default.fileExists(atPath: dest.path) {
                            let shouldOverwrite = await OverwriteDialog.ask(fileName: url.lastPathComponent)
                            if !shouldOverwrite { continue }
                            try? FileManager.default.removeItem(at: dest)
                        }
                        do {
                            try FileManager.default.copyItem(at: url, to: dest)
                        } catch {
                            appVM.presentError(error)
                        }
                    }
                }
                vm.refresh()
            }
            return true
        } isTargeted: { targeted in
            dragOver = targeted
        }
        .overlay(
            dragOver ? RoundedRectangle(cornerRadius: 4).stroke(.blue, lineWidth: 2).opacity(0.8) : nil
        )
        .contextMenu {
            Button {
                TextInputDialog.show(
                    title: "New Folder",
                    placeholder: "New Folder",
                    confirmLabel: "Create"
                ) { name in
                    guard let name, !name.isEmpty else { return }
                    let newDirURL = vm.currentURL.appendingPathComponent(name)
                    do {
                        try FileManager.default.createDirectory(at: newDirURL, withIntermediateDirectories: true)
                        vm.refresh()
                    } catch {
                        appVM.presentError(error)
                    }
                }
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        }
    }

    // MARK: - Column headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { vm.setSort(.name) }
                .overlay(sortIndicator(for: .name), alignment: .trailing)
            Divider().frame(height: 16)
            Text("Size")
                .frame(width: 70, alignment: .trailing)
                .onTapGesture { vm.setSort(.size) }
            Divider().frame(height: 16)
            Text("Modified")
                .frame(width: 110, alignment: .leading)
                .onTapGesture { vm.setSort(.date) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func sortIndicator(for col: LocalPaneViewModel.SortColumn) -> some View {
        if vm.sortColumn == col {
            Image(systemName: vm.sortAscending ? "chevron.up" : "chevron.down")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func sidebarIcon(for name: String) -> String {
        switch name.lowercased() {
        case "home":      return "house.fill"
        case "desktop":   return "desktopcomputer"
        case "documents": return "doc.fill"
        case "downloads": return "arrow.down.circle.fill"
        default:          return "folder.fill"
        }
    }
}

// MARK: - SidebarSection / Row

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 2)
            content()
        }
    }
}

struct SidebarRow: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .frame(width: 14)
                    .foregroundStyle(isSelected ? .white : .accentColor)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}
