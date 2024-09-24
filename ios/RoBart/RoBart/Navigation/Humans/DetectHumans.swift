//
//  DetectHumans.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/23/24.
//


import ARKit
import CoreGraphics
import CoreImage
import Vision
import UIKit

func detectHumans(in frame: ARFrame, maximumDistance: Float = 2) -> [Vector3] {
    var timer = Util.Stopwatch()
    timer.start()

    // Get depth map and filter it to preserve only high confidence values
    guard let depthMap = frame.sceneDepth?.depthMap,
          let depthConfidence = frame.sceneDepth?.confidenceMap else {
        return []
    }
    filterDepthMap(depthMap, depthConfidence, UInt8(ARConfidenceLevel.high.rawValue))
    log("Filter depth map: \(timer.elapsedMilliseconds()) ms")

    // Get depth intrinsic parameters
    let scaleX = Float(depthMap.width) / Float(frame.capturedImage.width)
    let scaleY = Float(depthMap.height) / Float(frame.capturedImage.height)
    let fx = frame.camera.intrinsics[0,0] * scaleX
    let cx = frame.camera.intrinsics[2,0] * scaleX   // note: (column, row)
    let fy = frame.camera.intrinsics[1,1] * scaleY
    let cy = frame.camera.intrinsics[2,1] * scaleY

    // Create a depth camera to world matrix. The depth image coordinate system happens to be
    // almost the same as the ARKit camera system, except y is flipped (everything rotated 180
    // degrees about the x axis, which points down in portrait orientation).
    let rotateDepthToARKit = Quaternion(angle: .pi, axis: .right)
    let viewMatrix = frame.camera.transform
    let cameraToWorld = viewMatrix * Matrix4x4(translation: .zero, rotation: rotateDepthToARKit, scale: .one)

    // Perform human segmentation
    timer.start()
    let image = CIImage(cvPixelBuffer: frame.capturedImage)
    let request = VNGeneratePersonSegmentationRequest()
    let requestHandler = VNImageRequestHandler(ciImage: image)
    do {
        try requestHandler.perform([request])
    } catch {
        log("Error: \(error.localizedDescription)")
        return []
    }
    guard let buffer = request.results?.first else {
        return []
    }
    log("People segmentation: \(timer.elapsedMilliseconds()) ms")

    // Extract 2D boxes containing humans. Use the depth map resolution.
    timer.start()
    guard let segmentationBuffer = buffer.pixelBuffer.resize(newWidth: depthMap.width, newHeight: depthMap.height) else { return [] }
    let boxes = findHumans(segmentationBuffer, 200)
    log("Human bounding boxes: \(timer.elapsedMilliseconds()) ms")

    // Get average depth for each person
    timer.start()
    var boxesWithDepth: [(box: CGRect, distance: Float)] = []
    for box in boxes {
        let depth = computeAverageDepthOfBoundingBox(box, depthMap, maximumDistance)
        if depth > 0 {
            let cgBox = CGRect(x: CGFloat(box.x), y: CGFloat(box.y), width: CGFloat(box.width), height: CGFloat(box.height))
            boxesWithDepth.append((box: cgBox, distance: depth))
        }
    }
    log("Depth value calculation: \(timer.elapsedMilliseconds()) ms")

    // Convert to world space
    var worldPoints: [Vector3] = []
    for boxWithDepth in boxesWithDepth {
        let worldPoint = convertDepthMapPointToWorldSpace(
            x: Float(boxWithDepth.box.midX),
            y: Float(boxWithDepth.box.midY),
            distance: boxWithDepth.distance,
            cameraToWorld: cameraToWorld,
            fx: fx,
            fy: fy,
            cx: cx,
            cy: cy
        )
        worldPoints.append(worldPoint)
    }

    return worldPoints
}

fileprivate func convertDepthMapPointToWorldSpace(x: Float, y: Float, distance: Float, cameraToWorld: Matrix4x4, fx: Float, fy: Float, cx: Float, cy: Float) -> Vector3 {
    let cameraSpacePos = Vector3(x: distance * (Float(x) - cx) / fx , y: distance * (Float(y) - cy) / fy, z: distance)
    let worldPos = cameraToWorld.transformPoint(cameraSpacePos)
    return worldPos
}

fileprivate func drawBoundingBoxes(on pixelBuffer: CVPixelBuffer, segmentationMask segmentationMaskPixelBuffer: CVPixelBuffer, boxes: [CGRect] = []) -> UIImage? {
    // Create an image we will draw over
    guard let image = UIImage(pixelBuffer: pixelBuffer) else { return nil }

    // Draw original image
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    image.draw(in: CGRect(origin: .zero, size: image.size))

    // Draw boxes
    context.setFillColor(UIColor.green.cgColor)
    context.setStrokeColor(UIColor.green.cgColor)
    context.setLineWidth(2.0)
    for box in boxes {
        context.beginPath()
        context.move(to: box.origin)
        context.addLine(to: CGPoint(x: box.maxX, y: box.minY)) // Top line
        context.addLine(to: CGPoint(x: box.maxX, y: box.maxY)) // Right line
        context.addLine(to: CGPoint(x: box.minX, y: box.maxY)) // Bottom line
        context.addLine(to: CGPoint(x: box.minX, y: box.minY)) // Left line (back to origin)
        context.closePath()
        context.strokePath()
    }

    // Draw human pixels
//    guard let instanceMask = instanceMaskPixelBuffer.toUInt8Array() else { return nil }
//    let scaleXX = CGFloat(instanceMaskPixelBuffer.width) / CGFloat(pixelBuffer.width)
//    let scaleYY =  CGFloat(instanceMaskPixelBuffer.height) / CGFloat(pixelBuffer.height)
//    for y in 0..<pixelBuffer.height {
//        for x in 0..<pixelBuffer.width {
//            let xx = CGFloat(x)
//            let yy = CGFloat(y)
//            let xi = Int(xx * scaleXX)
//            let yi = Int(yy * scaleYY)
//            let value = instanceMask[yi * instanceMaskPixelBuffer.width + xi]
//            if value > 128 {
//                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
//            }
//        }
//    }

    // Return new image
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return newImage
}

fileprivate func log(_ message: String) {
    print("[DetectHumans] \(message)")
}
