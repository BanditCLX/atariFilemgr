// LocalFileRowView.swift — AtariFileMgr
// A single row in the local macOS filesystem pane.

import SwiftUI

struct LocalFileRowView: View {
    let item: LocalItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: item.systemImage)
                .frame(width: 16)
                .foregroundStyle(item.isDirectory ? .yellow : .blue)

            // Name
            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Size
            Text(item.sizeString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            // Date
            Text(item.dateString)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .background(
            isSelected
            ? Color.accentColor.opacity(0.2)
            : Color.clear
        )
    }
}
