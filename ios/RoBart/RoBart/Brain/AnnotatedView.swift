//
//  AnnotatedView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/18/24.
//
//  Takes a photo (of the robot's current view) and adds annotations for the AI to analyze.
//

import Foundation
import RealityKit
import UIKit

fileprivate func placeEntityInScene(offset: Vector3) -> Vector3 {
    let mesh = MeshResource.generateBox(size: 0.1)
    let modelEntity = ModelEntity(mesh: mesh, materials: [ SimpleMaterial(color: UIColor.gray, isMetallic: true) ])
    let inFront = ARSessionManager.shared.transform.position - ARSessionManager.shared.transform.forward
    let inFrontOnFloor = Vector3(inFront.x, ARSessionManager.shared.floorY, inFront.z) + offset
    let entity = AnchorEntity(world: inFrontOnFloor)
    entity.addChild(modelEntity)
    ARSessionManager.shared.scene?.addAnchor(entity)
    return inFrontOnFloor
}

fileprivate func placePoint(at position: Vector3) {
    let mesh = MeshResource.generateBox(size: 0.1)
    let modelEntity = ModelEntity(mesh: mesh, materials: [ SimpleMaterial(color: UIColor.red, isMetallic: true) ])
    let entity = AnchorEntity(world: position)
    entity.addChild(modelEntity)
    ARSessionManager.shared.scene?.addAnchor(entity)
}

fileprivate struct NavigablePoint {
    let id: Int
    let worldPoint: Vector3
    let worldToCamera: Matrix4x4
    let intrinsics: Matrix3x3

    /// Image point with origin in lower-left (+y is up).
    var imagePoint: CGPoint {
        // Transform and project to image space
        let cameraPoint = worldToCamera.transformPoint(worldPoint)
        let homogeneous = Vector3(x: -cameraPoint.y / cameraPoint.z, y: cameraPoint.x / cameraPoint.z, z: 1) // need to swap x<->y to compensate for image rotation
        let projected = intrinsics * homogeneous
        return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
    }

    var textColor: UIColor {
        return UIColor.white
    }

    var backgroundColor: CGColor {
        return UIColor.black.cgColor
    }
}

fileprivate func adjustIntrinsicsForClockwise90RotationAndNewSize(intrinsics: Matrix3x3, scale: Vector2) -> Matrix3x3 {
    /*
     * ARKit frame appears rotated counter-clockwise when holding the phone in portrait
     * orientation, with the image's horizontal dimension being the phone's vertical one.
     * Therefore, we rotate the image clockwise and then downsample it to be more efficient when
     * submitting to the AI.
     *
     * The camera intrinsics need to be adjusted for these changes by swapping x and y and then
     * scaling appropriately by newDimension / oldDimension.
     */
    let fx = intrinsics[0,0]
    let fy = intrinsics[1,1]
    let cx = intrinsics[2,0]
    let cy = intrinsics[2,1]
    let cw = intrinsics[2,2]
    return Matrix3x3(columns: ([ scale.x * fy, 0, 0 ], [ 0, scale.y * fx, 0 ], [ scale.x * cy, scale.y * cx, cw ]))
}

fileprivate func annotate(image: UIImage, with points: [NavigablePoint]) -> UIImage? {
    let sideLength = CGFloat(20)

    // Get the image size
    let imageSize = image.size
    let scale = image.scale

    // Draw original image
    UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    image.draw(in: CGRect(origin: .zero, size: imageSize))

    // Draw annotations
    for point in points {
        // Draw square
        let y = imageSize.height - point.imagePoint.y   // to UIKit upper-left origin
        let squareRect = CGRect(x: point.imagePoint.x, y: y, width: sideLength, height: sideLength)
        context.setFillColor(point.backgroundColor)
        context.fill(squareRect)

        // Draw number in center of square
        let text = "\(point.id)"
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: sideLength / 2, weight: .bold),
            .foregroundColor: point.textColor
        ]
        let textSize = text.size(withAttributes: textAttributes)
        let textX = squareRect.midX - textSize.width / 2
        let textY = squareRect.midY - textSize.height / 2
        let textRect = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)
        text.draw(in: textRect, withAttributes: textAttributes)
    }

    // Return new image
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return newImage
}


@MainActor
func takePhotoWithAnnotations() async -> Data? {
    var worldPoints: [Vector3] = []
    let ourTransform = ARSessionManager.shared.transform
    let ourPosition = Vector3(x: ourTransform.position.x, y: ARSessionManager.shared.floorY, z: ourTransform.position.z)
    let forward = -ourTransform.forward.xzProjected.normalized
    for angle in [ 15.0, 0.0, 15.0  ] {
        let forward = forward.rotated(by: Float(angle), about: .up)
        for i in 2...5 {
            let position = ourPosition + forward * Float(i) * 0.75
            placePoint(at: position)
            worldPoints.append(position)
        }
    }

    // Wait for next frame
    guard let frame = try? await ARSessionManager.shared.nextFrame() else { return nil }

    // Produce rotate (portrait mode) image and corresponding intrinsics
    let originalSize = frame.camera.imageResolution
    let newSize = CGSize(width: 640, height: 480)   // before rotation!
    guard let photo = UIImage(pixelBuffer: frame.capturedImage)?.resized(to: newSize).rotatedClockwise90() else { return nil }
    let scale = Vector2(x: Float(newSize.height / originalSize.height), y: Float(newSize.width / originalSize.width))
    let intrinsics = adjustIntrinsicsForClockwise90RotationAndNewSize(intrinsics: frame.camera.intrinsics, scale: scale)

    // Annotations
    var points: [NavigablePoint] = []
    let worldToCamera = frame.camera.transform.inverse
    for i in 0..<worldPoints.count {
        points.append(NavigablePoint(id: i, worldPoint: worldPoints[i], worldToCamera: worldToCamera, intrinsics: intrinsics))
    }
    guard let annotatedPhoto = annotate(image: photo, with: points),
          let jpeg = annotatedPhoto.jpegData(compressionQuality: 0.8) else { return nil }
    return jpeg
}
