//
//  SmartCamera.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/18/24.
//
//  Takes a photo (of the robot's current view) and adds annotations for the AI to analyze.
//

import ARKit
import UIKit

class SmartCamera {
    private var _imageID = 0
    private var _pointID = 0

    struct Photo {
        let name: String
        let jpegBase64: String
        let navigablePoints: [NavigablePoint]
    }

    struct NavigablePoint {
        let id: Int
        let worldPoint: Vector3
        let worldToCamera: Matrix4x4
        let intrinsics: Matrix3x3

        /// Image point with origin in lower-left (+y is up).
        var imagePoint: CGPoint {
            /*
             * Transform world point to view space. Note that the *camera* space in ARKit is:
             *      ---> +y
             *      +----+
             *      |    | |
             *      |    | |
             *      |    | V
             *      |    | +x
             *      +----+
             *
             * Assuming the phone is held in portrait mode. The way the camera sensor is oriented, the
             * image we get is:
             *
             *      --> +x
             *   +y +------------+
             *    ^ |            |
             *    | |            |
             *    | +------------+
             *
             * With +z pointing out of the screen. However, the viewspace coordinates are not quite the
             * same. They are:
             *
             *      --> +x
             *    | +------------+
             *    | |            |
             *    V |            |
             *   +y +------------+
             *
             * With +z pointing into the screen (into the scene from the back side of the phone). This
             * is what the intrinsic matrix assumes. Therefore, we must rotate 180 degrees about the x
             * axis to invert both y and z. Or just multiply these components on a position in camera
             * space by -1, as we do here. Note that this coordinate system maps onto the typical
             * upper-left origin 2D bitmap (x,y) space.
             */
            var cameraPoint = worldToCamera.transformPoint(worldPoint)
            cameraPoint.y *= -1
            cameraPoint.z *= -1

            // Project onto the 2D frame where the origin is in the upper-left and +y is down
            let homogeneous = Vector3(x: cameraPoint.x / cameraPoint.z, y: cameraPoint.y / cameraPoint.z, z: 1)
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

    @MainActor
    func takePhoto() async -> Photo? {
        // Update occupancy
        _ = await NavigationController.shared.updateOccupancy()

        // Wait for next frame and acquire photo with necessary transforms for converting from world
        // -> image space
        guard let frame = try? await ARSessionManager.shared.nextFrame(),
              let cameraImage = getCameraImage(from: frame) else {
            return nil
        }
        let worldToCamera = frame.camera.transform.inverse

        // Get navigable points
        let possibleNagivablePoints = generateProspectiveNavigablePoints(worldToCamera: worldToCamera, intrinsics: cameraImage.intrinsics)
        let navigablePoints = excludeUnreachable(possibleNagivablePoints, ourPosition: ARSessionManager.shared.transform.position, occupancy: NavigationController.shared.occupancy)

        // Rotate photo and render navigable points as annotations
        guard let rotatedPhoto = cameraImage.image.rotatedClockwise90(),
              let annotatedPhoto = annotate(image: rotatedPhoto, with: navigablePoints, rotated: true) else {
            return nil
        }

        // Get JPEG
        guard let jpegBase64 = annotatedPhoto.jpegData(compressionQuality: 0.8)?.base64EncodedString() else { return nil }

        // Return all data
        let name = "photo\(_imageID)"
        _imageID += 1
        return Photo(name: name, jpegBase64: jpegBase64, navigablePoints: navigablePoints)
    }

    /// Generate a series of potential navigable points on the floor in front of the robot.
    /// - Parameter worldToCamera: Inverse camera transform matrix (i.e., world to camera-local space).
    /// - Parameter intrinsics: Camera intrinsics. Used with `worldToCamera`to convert world-space
    /// points to image-space annotations.
    /// - Returns: Array of prospective navigable points. None are guaranteed to be reachable.
    private func generateProspectiveNavigablePoints(worldToCamera: Matrix4x4, intrinsics: Matrix3x3) -> [NavigablePoint] {
        // Generate points on the floor in world space in front of the robot
        var worldPoints: [Vector3] = []
        let ourTransform = ARSessionManager.shared.transform
        let ourPosition = Vector3(x: ourTransform.position.x, y: ARSessionManager.shared.floorY, z: ourTransform.position.z)
        let forward = -ourTransform.forward.xzProjected.normalized
        for angle in [ 20.0, 0.0, -20.0 ] {
            let forward = forward.rotated(by: Float(angle), about: .up)
            for i in 2...5 {
                let position = ourPosition + forward * Float(i) * 0.75
                worldPoints.append(position)
            }
        }

        // Convert to navigable points
        var navigablePoints: [NavigablePoint] = []
        for worldPoint in worldPoints {
            navigablePoints.append(NavigablePoint(id: _pointID, worldPoint: worldPoint, worldToCamera: worldToCamera, intrinsics: intrinsics))
            _pointID = (_pointID + 1) % 100 // wrap around so numbers don't get too long
        }
        return navigablePoints
    }

    /// Given a set of navigable points, excludes those which are not reachable via a straight line
    /// path from our position.
    /// - Parameter points: The candidate points.
    /// - Parameter ourPosition: Our (robot) world-space position.
    /// - Parameter occupancy: Occupancy map, which is used to determine if straight-line paths are
    /// clear.
    /// - Returns: Points that are reachable.
    private func excludeUnreachable(_ points: [NavigablePoint], ourPosition: Vector3, occupancy: OccupancyMap) -> [NavigablePoint] {
        return points.filter { occupancy.isLineUnobstructed(ourPosition, $0.worldPoint) }
    }

    /// Obtains the camera image from the frame and scales it down to be more manageable to
    /// process. This image is oriented horizontally, as the camera sensor on iPhone returns
    /// images.
    private func getCameraImage(from frame: ARFrame) -> (image: UIImage, intrinsics: Matrix3x3)? {
        let originalSize = frame.camera.imageResolution
        let newSize = CGSize(width: 640, height: 480)   // before rotation!
        guard let cameraImage = UIImage(pixelBuffer: frame.capturedImage)?.resized(to: newSize) else { return nil }
        let scale = Vector2(x: Float(newSize.width / originalSize.width), y: Float(newSize.height / originalSize.height))
        let intrinsics = scaleIntrinsics(intrinsics: frame.camera.intrinsics, scale: scale)
        return (image: cameraImage, intrinsics: intrinsics)
    }

    /// Given a camera intrinsic matrix produces a copy scaled for a new image size.
    /// - Parameter intrinsics: Camera intrinsic matrix.
    /// - Parameter scale: Scale factors for the width and height: newResolution / oldResolution.
    /// - Returns: Intrinsic matrix that can be used with the scaled image.
    private func scaleIntrinsics(intrinsics: Matrix3x3, scale: Vector2) -> Matrix3x3 {
        var scaled = intrinsics
        scaled[0,0] *= scale.x  // fx
        scaled[2,0] *= scale.x  // cx
        scaled[1,1] *= scale.y  // fy
        scaled[2,1] *= scale.y  // cy
        return scaled
    }

    /// Renders navigable points as annotations on the image (squares with numbers inside of them).
    /// Necessary adjustments are made if the image has been rotated into a portrait orientation.
    /// - Parameter image: The image to annotate.
    /// - Parameter with: Points to annotate.
    /// - Parameter rotated: If `true`, the image is rotated clockwise 90 degrees relative to how
    /// the points are specified. The points will be adjusted accordingly.
    /// - Returns: New image with annotations or `nil` if anything went wrong.
    private func annotate(image: UIImage, with points: [NavigablePoint], rotated: Bool) -> UIImage? {
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
            // Draw square. Note that when rotating image clockwise and using an upper-left
            // origin with +y as down, it is necessary to invert x (because +y in the original
            // image moves down, but rotated clockwise, that direction is -x instead of +x).
            let imagePoint = point.imagePoint
            let x = rotated ? (imageSize.width - imagePoint.y) : imagePoint.x
            let y = rotated ? imagePoint.x : imagePoint.y
            let squareRect = CGRect(x: x, y: y, width: sideLength, height: sideLength)
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
}
