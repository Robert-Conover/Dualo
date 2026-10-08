//
//  ImageAttachmentView.swift
//  Dualo
//
//  Created by Robert Conover on 12/6/25.
//

import SwiftUI

struct ImageAttachmentView: View {
    let attachment: MessageAttachment
    @State private var isFullScreen = false
    @State private var decodedImage: UIImage?

    var body: some View {
        Group {
            if let uiImage = decodedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        isFullScreen = true
                    }
                    .fullScreenCover(isPresented: $isFullScreen) {
                        FullScreenImageView(image: uiImage, isPresented: $isFullScreen)
                    }
            } else {
                // Fallback / loading placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .task(id: attachment.data) {
            if let imageData = Data(base64Encoded: attachment.data) {
                decodedImage = UIImage(data: imageData)
            }
        }
    }
}

struct FullScreenImageView: View {
    let image: UIImage
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1.0), 4.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                }
                        )
                        .gesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        scale = scale > 1.0 ? 1.0 : 2.0
                                    }
                                }
                        )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background(.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Image", image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Pending Attachment Preview (for input bar)

struct PendingAttachmentPreview: View {
    let attachments: [ImageAttachment]
    let onRemove: (ImageAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: attachment.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button(action: { onRemove(attachment) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .dynamicTypeSize(...DynamicTypeSize.xxLarge) // Sits on a fixed-size thumbnail
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}
