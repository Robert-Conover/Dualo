//
//  ChatOptionsMenu.swift
//  Dualo
//

import SwiftUI

/// Toolbar "…" menu: rename the chat or export it.
struct ChatOptionsMenu: View {
    let isDisabled: Bool
    let onRename: () -> Void
    let onExport: (ChatExportService.Format) -> Void

    var body: some View {
        Menu {
            Button(action: onRename) {
                Label("Rename Chat", systemImage: "pencil")
            }

            Divider()

            ForEach(ChatExportService.Format.allCases, id: \.self) { format in
                Button(action: { onExport(format) }) {
                    Label("Export as \(format.displayName)", systemImage: format.systemImage)
                }
            }
        } label: {
            Label("Options", systemImage: "ellipsis")
        }
        .disabled(isDisabled)
    }
}
