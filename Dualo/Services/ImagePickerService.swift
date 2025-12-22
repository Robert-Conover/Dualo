//
//  ImagePickerService.swift
//  Dualo
//
//  Created by Robert Conover on 12/6/25.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Image Attachment (UI Layer)

struct ImageAttachment: Identifiable, Equatable {
    let id: UUID
    let image: UIImage
    let thumbnail: UIImage
    let mediaType: String

    // Maximum dimension for API uploads (keeps file size reasonable)
    private static let maxImageDimension: CGFloat = 1024

    init(image: UIImage, mediaType: String = "image/jpeg") {
        self.id = UUID()
        // Resize image if needed to keep payload size manageable
        self.image = Self.resizeImageIfNeeded(image, maxDimension: Self.maxImageDimension)
        self.thumbnail = image.preparingThumbnail(of: CGSize(width: 120, height: 120)) ?? image
        self.mediaType = mediaType
    }

    var base64Data: String? {
        // Use lower compression quality to reduce payload size
        guard let jpegData = image.jpegData(compressionQuality: 0.6) else { return nil }
        return jpegData.base64EncodedString()
    }

    func toMessageAttachment() -> MessageAttachment? {
        guard let base64 = base64Data else { return nil }
        return MessageAttachment(
            id: id,
            data: base64,
            mediaType: mediaType,
            width: Int(image.size.width),
            height: Int(image.size.height)
        )
    }

    static func == (lhs: ImageAttachment, rhs: ImageAttachment) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Image Resizing

    private static func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size

        // Check if resizing is needed
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        // Calculate new size maintaining aspect ratio
        let aspectRatio = size.width / size.height
        let newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        // Render resized image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resizedImage
    }
}

// MARK: - PHPicker SwiftUI Wrapper

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [ImageAttachment]
    let selectionLimit: Int
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = selectionLimit
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true) {
                self.parent.onDismiss()
            }

            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                        if let image = object as? UIImage {
                            DispatchQueue.main.async {
                                let attachment = ImageAttachment(image: image)
                                self?.parent.selectedImages.append(attachment)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var capturedImage: ImageAttachment?
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.capturedImage = ImageAttachment(image: image)
                }
            }
            picker.dismiss(animated: true) {
                self.parent.onDismiss()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.parent.onDismiss()
            }
        }
    }
}
