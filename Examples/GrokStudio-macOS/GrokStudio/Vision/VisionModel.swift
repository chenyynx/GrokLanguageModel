//
//  VisionModel.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import CoreGraphics
import Foundation
import FoundationModels
import GrokLanguageModel
import ImageIO
import Observation

/// Asks Grok a question about an image attachment.
@Observable
final class VisionModel {
    static let sampleQuestions = [
        "What's in this image? Describe it in a few sentences.",
        "Read all of the text in this image.",
        "What colors and shapes do you see?",
        "Write a short, playful caption for this image.",
    ]

    private(set) var image: CGImage?
    private(set) var imageName: String?
    var question = sampleQuestions[0]
    private(set) var answer = ""
    private(set) var usage: LanguageModelSession.Usage?
    private(set) var session: LanguageModelSession?
    private(set) var isResponding = false
    var error: PresentableError?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    var canAsk: Bool {
        image != nil && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    /// Loads an image that the user dropped or chose.
    func loadImage(from url: URL) {
        loadTask?.cancel()
        loadTask = Task {
            let image = await Self.downsampledImage(at: url)
            guard !Task.isCancelled else { return }
            guard let image else {
                error = PresentableError(
                    title: "Couldn't Open the Image",
                    message: "GrokStudio can't read “\(url.lastPathComponent)” as an image."
                )
                return
            }
            setImage(image, named: url.lastPathComponent)
        }
    }

    /// Decodes an image file off the main actor.
    ///
    /// Large photos are downsampled to at most 2048 pixels on a side, which
    /// keeps requests small, applies the photo's orientation, and handles
    /// any format that Image I/O reads, like HEIC.
    @concurrent private static func downsampledImage(at url: URL) async -> CGImage? {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// Loads a generated image with shapes and text to ask about.
    func useSampleImage() {
        loadTask?.cancel()
        guard let image = SampleImage.make() else { return }
        setImage(image, named: "Sample.png")
        question = Self.sampleQuestions[2]
    }

    func ask(using model: GrokModel) {
        guard let image, canAsk else { return }
        guard model.capabilities.contains(.vision) else {
            error = PresentableError(
                title: "Not Supported by This Model",
                message: "\(model.displayName) doesn't accept images.",
                suggestion: "Choose a different model from the toolbar."
            )
            return
        }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = imageName ?? "Image"
        stop()

        let session = LanguageModelSession(
            model: model,
            instructions: "Answer questions about images accurately and concisely."
        )
        self.session = session
        answer = ""
        usage = nil
        error = nil
        isResponding = true

        task = Task {
            do {
                // Grok models send image attachments as base64 data URLs.
                let response = try await session.respond {
                    question
                    Attachment(image).label(label)
                }
                if !Task.isCancelled {
                    answer = response.content
                    usage = response.usage
                }
            } catch {
                if !Task.isCancelled && !(error is CancellationError) {
                    self.error = PresentableError(error)
                }
            }
            if !Task.isCancelled {
                isResponding = false
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isResponding = false
    }

    private func setImage(_ image: CGImage, named name: String) {
        stop()
        self.image = image
        imageName = name
        answer = ""
        usage = nil
        error = nil
    }
}
