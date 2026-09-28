//
//  SampleImage.swift
//  GrokStudio
//
//  Created by Marcus Arnett on 9/28/26.
//

import AppKit
import CoreGraphics

/// Draws a sample image with shapes and text, so you can try the Vision
/// demo without choosing a file.
enum SampleImage {
    static func make() -> CGImage? {
        let width = 1024
        let height = 640
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }

        // A sky-to-grass background.
        let sky = [
            CGColor(srgbRed: 0.53, green: 0.78, blue: 0.98, alpha: 1),
            CGColor(srgbRed: 0.87, green: 0.94, blue: 1.0, alpha: 1),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: sky, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: CGFloat(height)),
                end: CGPoint(x: 0, y: 160),
                options: [.drawsAfterEndLocation]
            )
        }
        context.setFillColor(CGColor(srgbRed: 0.36, green: 0.68, blue: 0.33, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 160))

        // A red circle, a yellow triangle, and a blue square.
        context.setFillColor(CGColor(srgbRed: 0.90, green: 0.22, blue: 0.21, alpha: 1))
        context.fillEllipse(in: CGRect(x: 110, y: 180, width: 220, height: 220))

        context.setFillColor(CGColor(srgbRed: 0.98, green: 0.78, blue: 0.18, alpha: 1))
        context.move(to: CGPoint(x: 512, y: 410))
        context.addLine(to: CGPoint(x: 395, y: 180))
        context.addLine(to: CGPoint(x: 629, y: 180))
        context.closePath()
        context.fillPath()

        context.setFillColor(CGColor(srgbRed: 0.20, green: 0.40, blue: 0.86, alpha: 1))
        context.fill(CGRect(x: 704, y: 180, width: 210, height: 210))

        // A greeting across the top.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let greeting = NSAttributedString(string: "Hello, Grok!", attributes: [
            .font: NSFont.systemFont(ofSize: 76, weight: .heavy),
            .foregroundColor: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.28, alpha: 1),
        ])
        let size = greeting.size()
        greeting.draw(at: CGPoint(x: (CGFloat(width) - size.width) / 2, y: 460))
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }
}
