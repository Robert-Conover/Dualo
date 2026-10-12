//
//  CellularDownloadAlert.swift
//  Dualo
//
//  Models are hundreds of megabytes or more, so a download on cellular data or a
//  hotspot asks first, saying how big it is.
//

import SwiftUI

extension View {
    /// Asks before downloading `model` on cellular data; setting it shows the alert.
    func cellularDownloadAlert(for model: Binding<LocalModel?>, onDownload: @escaping (LocalModel) -> Void) -> some View {
        alert(
            "Download on Cellular?",
            isPresented: Binding(get: { model.wrappedValue != nil }, set: { if !$0 { model.wrappedValue = nil } }),
            presenting: model.wrappedValue
        ) { pending in
            Button("Download") { onDownload(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text("\(pending.displayName) is \(pending.formattedSize). Downloading it on cellular data uses your data plan, or you can wait for Wi-Fi.")
        }
    }
}
