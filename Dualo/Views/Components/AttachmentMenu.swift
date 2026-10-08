//
//  AttachmentMenu.swift
//  Dualo
//
//  The composers' + button. A menu rather than a confirmation dialog, so the
//  choices open from the button instead of from the top of the screen.
//

import SwiftUI

struct AttachmentMenu: View {
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    var color: Color = .blue

    var body: some View {
        Menu {
            Button("Photo Library", systemImage: "photo.on.rectangle") {
                showPhotoPicker = true
            }
            Button("Take Photo", systemImage: "camera") {
                showCamera = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.callout.weight(.medium))
                .foregroundStyle(color)
                .frame(minWidth: 24, minHeight: 24)
        }
        .accessibilityLabel("Add Attachment")
    }
}
