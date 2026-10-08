//
//  ChatModifiers.swift
//  Dualo
//
//  Alerts and attachment pickers for SimpleChatView, kept as modifiers so the
//  view's body stays small enough for the compiler to type-check quickly.
//

import SwiftUI

// MARK: - Alerts

struct ChatAlertsModifier: ViewModifier {
    @Binding var showError: Bool
    let errorMessage: String
    @Binding var showRenameAlert: Bool
    @Binding var newTitle: String
    @Binding var showExportError: Bool
    let exportErrorMessage: String
    @Binding var showModelLoadError: Bool
    let modelLoadErrorMessage: String
    let renameChat: (String) -> Void

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                }
            } message: {
                Text(errorMessage)
            }
            .alert("Rename Chat", isPresented: $showRenameAlert) {
                TextField("Chat Title", text: $newTitle)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedTitle.isEmpty {
                        renameChat(trimmedTitle)
                    }
                }
            } message: {
                Text("Enter a new title for this chat")
            }
            .alert("Export Error", isPresented: $showExportError) {
                Button("OK") { }
            } message: {
                Text(exportErrorMessage)
            }
            .alert("Model Load Error", isPresented: $showModelLoadError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(modelLoadErrorMessage)
            }
    }
}

// MARK: - Attachment Pickers

struct AttachmentPickerModifier: ViewModifier {
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var pendingAttachments: [ImageAttachment]
    @Binding var capturedImage: ImageAttachment?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(selectedImages: $pendingAttachments, selectionLimit: 4) {
                    showPhotoPicker = false
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(capturedImage: $capturedImage) {
                    showCamera = false
                }
            }
            .onChange(of: capturedImage) { oldValue, newValue in
                if let newImage = newValue {
                    pendingAttachments.append(newImage)
                    capturedImage = nil
                }
            }
    }
}
