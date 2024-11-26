//
//  CVPixelBuffer+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/7/24.
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

    var bytesPerRow: Int {
        return CVPixelBufferGetBytesPerRow(self)
    }

    var format: OSType {
        return CVPixelBufferGetPixelFormatType(self)
    }

    func toUInt8Array() -> [UInt8]? {
        guard CVPixelBufferGetPixelFormatType(self) == kCVPixelFormatType_OneComponent8 else {
            log("Error: toUInt8Array() currently only supports 8-bit single channel images")
            return nil
        }

        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else {
            return nil
        }

        if bytesPerRow == width {
            let byteBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            let byteArray = Array(UnsafeBufferPointer(start: byteBuffer, count: width * height))
            return byteArray
        } else {
            var byteArray = Array(repeating: UInt8(0), count: width * height)
            byteArray.withUnsafeMutableBytes { rawBufferPointer in
                var srcPointer = baseAddress
                var destPointer = rawBufferPointer.baseAddress!
                for _ in 0..<height {
                    // Copy pixel row and advance by stride in source buffer
                    memcpy(destPointer, srcPointer, width)
                    srcPointer = srcPointer.advanced(by: bytesPerRow)
                    destPointer = destPointer.advanced(by: width)
                }
            }
            return byteArray
        }
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

    func copy() -> CVPixelBuffer? {
        // Create a new pixel buffer
        var newPixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferIOSurfacePropertiesKey: [:]  // no specific IOSurface properties
        ] as CFDictionary

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            self.width,
            self.height,
            self.format,
            attributes,
            &newPixelBuffer
        )

        guard status == kCVReturnSuccess, let newBuffer = newPixelBuffer else {
            return nil
        }

        // Copy pixel data
        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags.readOnly)
        CVPixelBufferLockBaseAddress(newBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let originalBaseAddress = CVPixelBufferGetBaseAddress(self)
        let newBaseAddress = CVPixelBufferGetBaseAddress(newBuffer)
        let originalBytesPerRow = CVPixelBufferGetBytesPerRow(self)
        let newBytesPerRow = CVPixelBufferGetBytesPerRow(newBuffer)
        for row in 0..<height {
            let src = originalBaseAddress!.advanced(by: row * originalBytesPerRow)
            let dst = newBaseAddress!.advanced(by: row * newBytesPerRow)
            memcpy(dst, src, min(originalBytesPerRow, newBytesPerRow))
        }
        CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags.readOnly)
        CVPixelBufferUnlockBaseAddress(newBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return newBuffer
    }

    func resize(newWidth: Int, newHeight: Int) -> CVPixelBuffer? {
        let format = CVPixelBufferGetPixelFormatType(self)
        switch format {
        case kCVPixelFormatType_DepthFloat32:
            return resizeDepthFloat32(newWidth: newWidth, newHeight: newHeight)
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return resizeYUV(newWidth: newWidth, newHeight: newHeight)
        case kCVPixelFormatType_OneComponent8:
            return resizeOneComponent8(newWidth: newWidth, newHeight: newHeight)
        default:
            log("Error: Unsupported pixel format")
            return nil
        }
    }

    private func resizeDepthFloat32(newWidth: Int, newHeight: Int) -> CVPixelBuffer? {
        var srcBuffer = vImage_Buffer()
        var dstBuffer = vImage_Buffer()

        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }

        srcBuffer.data = CVPixelBufferGetBaseAddress(self)
        srcBuffer.width = vImagePixelCount(width)
        srcBuffer.height = vImagePixelCount(height)
        srcBuffer.rowBytes = CVPixelBufferGetBytesPerRow(self)

        guard let outputBuffer = createOutputBuffer(width: newWidth, height: newHeight, format: kCVPixelFormatType_DepthFloat32) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        dstBuffer.data = CVPixelBufferGetBaseAddress(outputBuffer)
        dstBuffer.width = vImagePixelCount(newWidth)
        dstBuffer.height = vImagePixelCount(newHeight)
        dstBuffer.rowBytes = CVPixelBufferGetBytesPerRow(outputBuffer)

        let error = vImageScale_PlanarF(&srcBuffer, &dstBuffer, nil, vImage_Flags(0))
        return error == kvImageNoError ? outputBuffer : nil
    }

    private func resizeYUV(newWidth: Int, newHeight: Int) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }

        guard let outputBuffer = createOutputBuffer(width: newWidth, height: newHeight, format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        guard let srcY = CVPixelBufferGetBaseAddressOfPlane(self, 0),
              let srcUV = CVPixelBufferGetBaseAddressOfPlane(self, 1),
              let dstY = CVPixelBufferGetBaseAddressOfPlane(outputBuffer, 0),
              let dstUV = CVPixelBufferGetBaseAddressOfPlane(outputBuffer, 1) else {
            return nil
        }

        var srcYBuffer = vImage_Buffer(
            data: srcY,
            height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(self, 0)),
            width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(self, 0)),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(self, 0)
        )

        var srcUVBuffer = vImage_Buffer(
            data: srcUV,
            height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(self, 1)),
            width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(self, 1)),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(self, 1)
        )

        var dstYBuffer = vImage_Buffer(
            data: dstY,
            height: vImagePixelCount(newHeight),
            width: vImagePixelCount(newWidth),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(outputBuffer, 0)
        )

        var dstUVBuffer = vImage_Buffer(
            data: dstUV,
            height: vImagePixelCount(newHeight / 2),
            width: vImagePixelCount(newWidth / 2),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(outputBuffer, 1)
        )

        let yError = vImageScale_Planar8(&srcYBuffer, &dstYBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        let uvError = vImageScale_Planar8(&srcUVBuffer, &dstUVBuffer, nil, vImage_Flags(kvImageHighQualityResampling))

        guard yError == kvImageNoError, uvError == kvImageNoError else {
            return nil
        }

        return outputBuffer
    }

    private func resizeOneComponent8(newWidth: Int, newHeight: Int) -> CVPixelBuffer? {
        var srcBuffer = vImage_Buffer()
        var dstBuffer = vImage_Buffer()

        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }

        srcBuffer.data = CVPixelBufferGetBaseAddress(self)
        srcBuffer.width = vImagePixelCount(width)
        srcBuffer.height = vImagePixelCount(height)
        srcBuffer.rowBytes = CVPixelBufferGetBytesPerRow(self)

        guard let outputBuffer = createOutputBuffer(width: newWidth, height: newHeight, format: kCVPixelFormatType_OneComponent8) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        dstBuffer.data = CVPixelBufferGetBaseAddress(outputBuffer)
        dstBuffer.width = vImagePixelCount(newWidth)
        dstBuffer.height = vImagePixelCount(newHeight)
        dstBuffer.rowBytes = CVPixelBufferGetBytesPerRow(outputBuffer)

        let error = vImageScale_Planar8(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        return error == kvImageNoError ? outputBuffer : nil
    }

    private func createOutputBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, format, nil, &outputBuffer)
        return status == kCVReturnSuccess ? outputBuffer : nil
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
