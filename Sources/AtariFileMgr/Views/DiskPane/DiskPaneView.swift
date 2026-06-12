// DiskPaneView.swift — AtariFileMgr
// Right pane: browsing and editing the open Atari ST disk image.

import SwiftUI
import UniformTypeIdentifiers

struct DiskPaneView: View {
    @ObservedObject var vm: DiskPaneViewModel
    @ObservedObject var localVM: LocalPaneViewModel
    @EnvironmentObject var appVM: AppViewModel

    @State private var renameTarget: GEMDOSEntry?
    @State private var dragOver = false
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Path / breadcrumb bar
            breadcrumbBar

            Divider()

            if appVM.openDiskImage == nil {
                // Empty state
                emptyState
            } else {
                // File list
                VStack(spacing: 0) {
                    columnHeaders
                    Divider()
                    fileList
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        // Delete (Alert without TextField — works correctly)
        .alert("Delete \(vm.selectedEntries.count) item(s)?",
               isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { vm.deleteSelected() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(vm.errorMessage ?? "", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        }
    }

    // MARK: - Breadcrumb bar

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button(action: vm.goUp) {
                Image(systemName: "arrow.up")
                    .frame(width: 20, height: 20)
            }
            .disabled(vm.breadcrumbs.count <= 1)
            .buttonStyle(.plain)

            // Breadcrumb trail
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(vm.breadcrumbs.enumerated()), id: \.offset) { idx, crumb in
                        if idx > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        Button(crumb.name) {
                            vm.navigateToBreadcrumb(index: idx)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(idx == vm.breadcrumbs.count - 1 ? .primary : .secondary)
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                ToolbarIconButton(icon: "folder.badge.plus", tooltip: "New Folder (F7)") {
                    TextInputDialog.show(
                        title: "New Folder",
                        message: "Folder name (max. 8 characters, GEMDOS 8.3 format)",
                        placeholder: "NEWDIR",
                        confirmLabel: "Create"
                    ) { name in
                        guard let name else { return }
                        vm.createDirectory(name: name)
                    }
                }
                .disabled(appVM.openDiskImage == nil)

                ToolbarIconButton(icon: "trash", tooltip: "Delete (F8)") {
                    showDeleteConfirm = true
                }
                .disabled(vm.selectedEntries.isEmpty)

                ToolbarIconButton(icon: "pencil", tooltip: "Rename (F9)") {
                    guard let entry = vm.selectedEntries.first else { return }
                    TextInputDialog.show(
                        title: "Rename",
                        placeholder: entry.displayName,
                        defaultValue: entry.displayName,
                        confirmLabel: "Rename"
                    ) { newName in
                        guard let newName else { return }
                        vm.rename(entry, to: newName)
                    }
                }
                .disabled(vm.selectedEntries.count != 1)

                ToolbarIconButton(icon: "arrow.clockwise", tooltip: "Refresh") {
                    vm.refresh()
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.bar)
    }

    // MARK: - Column headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { vm.setSort(.name) }

            Divider().frame(height: 16)
            Text("Attr")
                .frame(width: 38)
                .onTapGesture { vm.setSort(.attr) }

            Divider().frame(height: 16)
            Text("Size")
                .frame(width: 76, alignment: .trailing)
                .onTapGesture { vm.setSort(.size) }

            Divider().frame(height: 16)
            Text("Date")
                .frame(width: 110, alignment: .leading)
                .onTapGesture { vm.setSort(.date) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - File list

    private var fileList: some View {
        Group {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.entries.isEmpty {
                Text("Directory is empty")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.entries) { entry in
                            let isSelected = vm.selectedEntries.contains(entry)
                            DiskFileRowView(
                                entry: entry,
                                isSelected: isSelected,
                                // Drop macOS files onto this folder
                                onURLDrop: entry.isDirectory ? { urls in
                                    let isFromLocalSelection = urls.contains { url in
                                        localVM.selectedItems.contains { $0.url == url }
                                    }
                                    if isFromLocalSelection && !localVM.selectedItems.isEmpty {
                                        let selectedURLs = localVM.selectedItems.map(\.url)
                                        vm.importFiles(urls: selectedURLs, intoCluster: entry.startCluster)
                                    } else {
                                        vm.importFiles(urls: urls, intoCluster: entry.startCluster)
                                    }
                                } : nil,
                                // Intra-disk move: another entry onto this folder
                                onEntryDrop: entry.isDirectory ? { draggedID in
                                    if let source = vm.entries.first(where: { $0.id == draggedID }) {
                                        vm.moveEntry(source, intoCluster: entry.startCluster)
                                    }
                                } : nil
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let flags = NSEvent.modifierFlags
                                if flags.contains(.command) {
                                    if vm.selectedEntries.contains(entry) {
                                        vm.selectedEntries.remove(entry)
                                    } else {
                                        vm.selectedEntries.insert(entry)
                                    }
                                } else if flags.contains(.shift), let last = vm.selectedEntries.first {
                                    if let lastIdx = vm.entries.firstIndex(of: last),
                                       let curIdx = vm.entries.firstIndex(of: entry) {
                                        let start = min(lastIdx, curIdx)
                                        let end = max(lastIdx, curIdx)
                                        vm.selectedEntries = Set(vm.entries[start...end])
                                    }
                                } else {
                                    vm.selectedEntries = [entry]
                                }
                            }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    if entry.isDirectory {
                                        vm.navigateTo(entry: entry)
                                    }
                                }
                            )
                            // Drag: entry as DiskEntryTransfer (for intra-disk move & extraction)
                            .draggable(DiskEntryTransfer(
                                entryID: entry.id,
                                tempURL: vm.prepareDragURL(for: entry) ?? URL(fileURLWithPath: "")
                            ))
                            .contextMenu {
                                Button {
                                    let destDir = localVM.currentURL
                                    let targets = vm.selectedEntries.contains(entry) ? vm.selectedEntries : [entry]
                                    Task {
                                        vm.isLoading = true
                                        for target in targets {
                                            do {
                                                try await vm.extractEntry(target, to: destDir)
                                            } catch {
                                                vm.errorMessage = error.localizedDescription
                                            }
                                        }
                                        localVM.refresh()
                                        vm.isLoading = false
                                    }
                                } label: {
                                    Label("Copy to Left", systemImage: "arrow.left.doc.on.doc")
                                }

                                Button {
                                    let destDir = localVM.currentURL
                                    let targets = vm.selectedEntries.contains(entry) ? vm.selectedEntries : [entry]
                                    Task {
                                        vm.isLoading = true
                                        for target in targets {
                                            do {
                                                try await vm.extractEntry(target, to: destDir)
                                                try appVM.filesystem?.delete(target)
                                                appVM.isDirty = true
                                            } catch {
                                                vm.errorMessage = error.localizedDescription
                                            }
                                        }
                                        vm.refresh()
                                        localVM.refresh()
                                        vm.isLoading = false
                                    }
                                } label: {
                                    Label("Move to Left", systemImage: "arrow.left")
                                }

                                Divider()

                                Button {
                                    TextInputDialog.show(
                                        title: "Rename",
                                        placeholder: entry.displayName,
                                        defaultValue: entry.displayName,
                                        confirmLabel: "Rename"
                                    ) { newName in
                                        guard let newName, !newName.isEmpty else { return }
                                        vm.rename(entry, to: newName)
                                    }
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    if !vm.selectedEntries.contains(entry) {
                                        vm.selectedEntries = [entry]
                                    }
                                    showDeleteConfirm = true
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
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL, .url], isTargeted: $dragOver) { providers in
                    loadURLs(from: providers) { urls in
                        guard !urls.isEmpty else { return }
                        let isFromLocalSelection = urls.contains { url in
                            localVM.selectedItems.contains { $0.url == url }
                        }
                        if isFromLocalSelection && !localVM.selectedItems.isEmpty {
                            let selectedURLs = localVM.selectedItems.map(\.url)
                            vm.importFiles(urls: selectedURLs)
                        } else {
                            vm.importFiles(urls: urls)
                        }
                    }
                    return true
                }
        )
        .overlay(
            dragOver
            ? RoundedRectangle(cornerRadius: 0)
                .stroke(Color.accentColor, lineWidth: 2)
                .opacity(0.5)
            : nil
        )
        .contextMenu {
            Button {
                TextInputDialog.show(
                    title: "New Folder",
                    placeholder: "NEWDIR",
                    confirmLabel: "Create"
                ) { name in
                    guard let name, !name.isEmpty else { return }
                    vm.createDirectory(name: name)
                }
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        }
    }


    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("No disk image open")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Use New or Open to load a disk image,\nor drag an .st / .msa file here.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            if let url = urls.first {
                let ext = url.pathExtension.lowercased()
                if ext == "st" || ext == "msa" {
                    appVM.openDisk(url: url)
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Extract URLs from NSItemProvider for onDrop
    private func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
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
}

// MARK: - ToolbarIconButton

struct ToolbarIconButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
