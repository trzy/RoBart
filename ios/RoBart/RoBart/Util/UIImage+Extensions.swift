//
//  UIImage+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/18/24.
//
//  This file is part of RoBart.
//
//  RoBart is free software: you can redistribute it and/or modify it under the
//  terms of the GNU General Public License as published by the Free Software
//  Foundation, either version 3 of the License, or (at your option) any later
//  version.
//
//  RoBart is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with RoBart. If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import CoreVideo
import VideoToolbox

extension UIImage {
    /// Creates a `UIImage` from a `CVPixelBuffer`. Not all `CVPixelBuffer` formats are supported.
    /// - Parameter pixelBuffer: The pixel buffer to create the image from.
    /// - Returns: `nil` if unsuccessful, otherwise `UIImage`.
    convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        guard let cgImage = cgImage else {
            log("Unable to create UIImage from pixel buffer")
            return nil
        }
        self.init(cgImage: cgImage)
    }

    func rotatedClockwise90() -> UIImage? {
        let originalSize = size
        let rotatedSize = CGSize(width: originalSize.height, height: originalSize.width)

        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Move origin to center of rotated image and rotate context by 90 degrees
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: .pi / 2)

        // Draw image in new position and size
        draw(in: CGRect(x: -originalSize.width / 2, y: -originalSize.height / 2, width: originalSize.width, height: originalSize.height))

        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotatedImage
    }

    func resized(to newSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0  // important or it will end up not actually resizing
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let newImage = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return newImage
    }

    func centerCropped(to cropSize: CGSize) -> UIImage? {
        guard let srcImage = self.cgImage else {
            log("Unable to obtain CGImage")
            return nil
        }

        // Must be careful to avoid rounding up anywhere!
        let xOffset = (size.width - cropSize.width) / 2.0
        let yOffset = (size.height - cropSize.height) / 2.0
        let cropRect = CGRect(x: CGFloat(Int(xOffset)), y: CGFloat(Int(yOffset)), width: CGFloat(Int(cropSize.width)), height: CGFloat(Int(cropSize.height)))

        guard let croppedImage = srcImage.cropping(to: cropRect) else {
            log("Failed to produce cropped CGImage")
            return nil
        }

        return UIImage(cgImage: croppedImage, scale: self.imageRendererFormat.scale, orientation: self.imageOrientation)
    }

    func expandImageWithLetterbox(to newSize: CGSize) -> UIImage? {
        assert(newSize.width >= self.size.width && newSize.height >= self.size.height, "Image can only be expanded")

        if newSize == self.size {
            return self
        }

        UIGraphicsBeginImageContext(newSize)
        defer {
            UIGraphicsEndImageContext()
        }
        guard let ctx = UIGraphicsGetCurrentContext() else {
            log("Unable to get current graphics context")
            return nil
        }

        // Fill new image with black and then draw old image in the middle
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill([ CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height) ])
        let xOffset = (newSize.width - self.size.width) / 2
        let yOffset = (newSize.height - self.size.height) / 2
        self.draw(in: CGRect(x: xOffset, y: yOffset, width: self.size.width, height: self.size.height))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        return newImage
    }

    /// Converts a `UIImage` to an ARGB-formatted `CVPixelBuffer`. The `UIImage` is assumed to be
    /// opaque and the alpha channel is ignored. The resulting pixel buffer has all alpha values set to `0xFF`.
    /// - Returns: `CVPixelBuffer` if successful otherwise `nil`.
    func toPixelBuffer() -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)

        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess,
              let pixelBuffer = pixelBuffer else {
            log("Error: Unable to create pixel buffer")
            return nil
        }

        let lockFlags = CVPixelBufferLockFlags(rawValue: 0)

        guard CVPixelBufferLockBaseAddress(pixelBuffer, lockFlags) == kCVReturnSuccess else {
            log("Error: Unable to lock pixel buffer")
            return nil
        }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, lockFlags)
            log("Error: Unable to create CGContext")
            return nil
        }

        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()

        return pixelBuffer
    }
}

fileprivate func log(_ message: String) {
    print("[UIImage] \(message)")
}
