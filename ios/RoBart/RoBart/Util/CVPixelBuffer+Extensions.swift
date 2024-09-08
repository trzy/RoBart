//
//  CVPixelBuffer+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/7/24.
//

import Accelerate
import CoreVideo
import UIKit

extension CVPixelBuffer {
    enum DepthColorScheme {
        case grayscale
        case jet
    }

    var width: Int {
        return CVPixelBufferGetWidth(self)
    }

    var height: Int {
        return CVPixelBufferGetHeight(self)
    }

    var format: OSType {
        return CVPixelBufferGetPixelFormatType(self)
    }

    func toFloatArray() -> [Float]? {
        guard CVPixelBufferGetPixelFormatType(self) == kCVPixelFormatType_DepthFloat32 else {
            log("Error: toFloatArray() currently only supports 32-bit depth images")
            return nil
        }
        CVPixelBufferLockBaseAddress(self, .readOnly)
        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else {
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
            return nil
        }
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let floatArray = Array(UnsafeBufferPointer(start: floatBuffer, count: width * height))
        CVPixelBufferUnlockBaseAddress(self, .readOnly)
        return floatArray
    }

    func resize(newWidth: Int, newHeight: Int) -> CVPixelBuffer? {
        guard format == kCVPixelFormatType_DepthFloat32 else {
            log("Error: resize() currently only supports 32-bit depth images")
            return nil
        }

        var srcBuffer = vImage_Buffer()
        var dstBuffer = vImage_Buffer()

        // Create vImage buffers for input and output
        CVPixelBufferLockBaseAddress(self, .readOnly)
        srcBuffer.data = CVPixelBufferGetBaseAddress(self)
        srcBuffer.width = vImagePixelCount(width)
        srcBuffer.height = vImagePixelCount(height)
        srcBuffer.rowBytes = CVPixelBufferGetBytesPerRow(self)

        var outputPixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, newWidth, newHeight, format, nil, &outputPixelBuffer)

        guard let outputBuffer = outputPixelBuffer else {
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
            return nil
        }

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        dstBuffer.data = CVPixelBufferGetBaseAddress(outputBuffer)
        dstBuffer.width = vImagePixelCount(newWidth)
        dstBuffer.height = vImagePixelCount(newHeight)
        dstBuffer.rowBytes = CVPixelBufferGetBytesPerRow(outputBuffer)

        // Perform resizing
        let error = vImageScale_PlanarF(&srcBuffer, &dstBuffer, nil, vImage_Flags(0))
        CVPixelBufferUnlockBaseAddress(self, .readOnly)
        CVPixelBufferUnlockBaseAddress(outputBuffer, [])

        return error == kvImageNoError ? outputBuffer : nil
    }

    /// Produces a `UIImage` visualizing the depth buffer. Requires that the `CVPixelBuffer` be a single-
    /// channel floating point buffer.
    /// - Parameter minDistance: Minimum of range of depth values (meters) to clamp to.
    /// - Parameter maxDistance: Maximum of range of depth values (meters) to clamp to. According
    /// to Apple's point cloud example, the maximum distance the LiDAR device supports is 5.0m. A
    /// maximum value of 2.5m is good for visualization of close-up scenes. See the code at:
    /// https://developer.apple.com/documentation/arkit/arkit_in_ios/environmental_analysis/displaying_a_point_cloud_using_scene_depth
    /// - Parameter colorScheme: Color scheme to use.
    /// - Returns: A `UIImage` if successful otherwise `nil` if an error occurred.
    ///
    func uiImageFromDepth(minDistance: Float = 0.0, maxDistance: Float = 5.0, colorScheme: DepthColorScheme = .grayscale) -> UIImage? {
        guard format == kCVPixelFormatType_DepthFloat32 else {
            log("Error: Depth buffer has unsupported format: \(format)")
            return nil
        }

        CVPixelBufferLockBaseAddress(self, .readOnly)

        let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(self), to: UnsafeMutablePointer<Float32>.self)
        var rgb = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let depthIdx = y * width + x
                let depthValue = floatBuffer[depthIdx]
                let normalized = (depthValue - minDistance) / (maxDistance - minDistance)
                let color = Self.getDepthColor(normalizedDepth: normalized, colorScheme: colorScheme)
                let pixelIdx = depthIdx * 4
                rgb[pixelIdx + 0] = UInt8(clamping: Int(255 * color.r))
                rgb[pixelIdx + 1] = UInt8(clamping: Int(255 * color.g))
                rgb[pixelIdx + 2] = UInt8(clamping: Int(255 * color.b))
                rgb[pixelIdx + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        if let dataProvider = CGDataProvider(data: Data(rgb) as CFData),
           let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent) {
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
            return UIImage(cgImage: cgImage)
        }

        CVPixelBufferUnlockBaseAddress(self, .readOnly)
        return nil
    }

    fileprivate static func getDepthColor(normalizedDepth: Float, colorScheme: DepthColorScheme) -> (r: Float, g: Float, b: Float) {
        switch colorScheme {
        case .grayscale:
            return (r: normalizedDepth, g: normalizedDepth, b: normalizedDepth)

        case .jet:
            if normalizedDepth <= 0.01 {
                return (r: 0, g: 0, b: 0)
            }
            let r = clamp(Float(1.5) - abs(4.0 * normalizedDepth - 3.0), min: Float(0.0), max: Float(1.0))
            let g = clamp(Float(1.5) - abs(4.0 * normalizedDepth - 2.0), min: Float(0.0), max: Float(1.0))
            let b = clamp(Float(1.5) - abs(4.0 * normalizedDepth - 1.0), min: Float(0.0), max: Float(1.0))
            return (r: r, g: g, b: b)
        }
    }
}

fileprivate func log(_ message: String) {
    print("[CVPixelBuffer] \(message)")
}
