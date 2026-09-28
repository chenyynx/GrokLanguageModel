//
//  ComposerView.swift
//  GrokChat
//
//  Created by Marcus Arnett on 9/28/26.
//

import CoreGraphics
import ImageIO
import PhotosUI
import SwiftUI

/// The bar at the bottom of the chat screen for writing a message and
/// attaching a photo.
struct ComposerView: View {
    @Binding var text: String
    @Binding var image: CGImage?
    var isResponding: Bool
    var send: () -> Void
    var stop: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image {
                AttachmentPreview(image: image) { self.image = nil }
            } else if isLoadingPhoto {
                ProgressView()
                    .frame(width: 64, height: 64)
                    .background(.fill.quinary, in: .rect(cornerRadius: 14))
                    .padding(6)
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Attach Photo")
                .disabled(isResponding)

                TextField("Ask Grok anything", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.vertical, 8)

                Button(action: isResponding ? stop : send) {
                    Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(isResponding || canSend ? AnyShapeStyle(.tint) : AnyShapeStyle(.gray.opacity(0.4)), in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(isResponding ? "Stop" : "Send")
                .disabled(!isResponding && !canSend)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .animation(.snappy, value: image != nil)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .task(id: photoItem) {
            await loadPhoto()
        }
    }

    private func loadPhoto() async {
        guard let item = photoItem else { return }
        isLoadingPhoto = true

        var photo: CGImage?
        if let data = try? await item.loadTransferable(type: Data.self) {
            photo = await Self.downsample(data, maxPixelSize: 1_536)
        }
        // Picking another photo while this one loads cancels this task and
        // starts one for the new photo, so leave the new selection alone.
        guard !Task.isCancelled, photoItem == item else { return }
        if let photo {
            image = photo
        }
        isLoadingPhoto = false
        photoItem = nil
    }

    /// Decodes a photo at a size that's large enough for the model to read, and
    /// small enough to upload quickly, with its orientation applied.
    @concurrent private static func downsample(_ data: Data, maxPixelSize: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A thumbnail of the photo that the next message will include.
private struct AttachmentPreview: View {
    var image: CGImage
    var remove: () -> Void

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                Button("Remove Photo", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .offset(x: 6, y: -6)
            }
            .padding(6)
    }
}
