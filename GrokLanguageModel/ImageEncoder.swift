//
//  ImageEncoder.swift
//  GrokLanguageModel
//
//  Created by Marcus Arnett on 9/28/26.
//

import CoreGraphics
import CoreImage
import Foundation
import FoundationModels
import ImageIO

/// Converts image attachments to the URLs that the xAI API accepts: a remote
/// URL, or a base64-encoded JPEG or PNG data URL.
enum ImageEncoder {
    private static let context = CIContext()

    static func url(for image: Transcript.ImageAttachment) throws -> String {
        if let url = image.url {
            if url.scheme == "https" || url.scheme == "http" {
                return url.absoluteString
            }
            if url.isFileURL, image.orientation == .up,
               let mimeType = mimeType(forPathExtension: url.pathExtension),
               let data = try? Data(contentsOf: url) {
                return dataURL(data, mimeType: mimeType)
            }
        }

        var ciImage = CIImage(cgImage: image.cgImage)
        if image.orientation != .up {
            ciImage = ciImage.oriented(image.orientation)
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.cgImage.alphaInfo)
        if hasAlpha, let data = context.pngRepresentation(of: ciImage, format: .RGBA8, colorSpace: colorSpace) {
            return dataURL(data, mimeType: "image/png")
        }
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.9]
        guard let data = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options) else {
            throw GrokError.imageEncodingFailed
        }
        return dataURL(data, mimeType: "image/jpeg")
    }

    private static func mimeType(forPathExtension pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        default: nil
        }
    }

    private static func dataURL(_ data: Data, mimeType: String) -> String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}
