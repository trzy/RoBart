//
//  AnnotatingCamera.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/18/24.
//
//  Takes a photo (of the robot's current view) and adds annotations for the AI to analyze.
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

import ARKit
import UIKit

class AnnotatingCamera {
    enum Annotation {
        case navigablePoints
        case headingAndDistanceGuides
    }

    struct Photo {
        /// A unique photo identifier.
        let name: String

        /// Original image, without any annotations.
        let originalImage: UIImage

        /// Annotated image
        let annotatedImage: UIImage

        /// JPEG data, with annotations if applicable. This is the image that should be sent to AI.
        let annotatedJPEGBase64: String

        let navigablePoints: [NavigablePoint]
        let worldToCamera: Matrix4x4?
        let intrinsics: Matrix3x3?
        let position: Vector3?
        let forward: Vector3?
        let headingDegrees: Float?

        func findNavigablePoint(id: Int) -> NavigablePoint? {
            return navigablePoints.first(where: { $0.id == id })
        }

        /// Creates a `Photo` object without any annotations that does not correspond to a camera
        /// image.
        /// - Parameter name: A name for the photo.
        /// - Parameter originalImage; The image.
        /// - Returns: `Photo` object if successful else `nil`.
        static func createWithoutAnnotations(name: String, originalImage: UIImage) -> Photo? {
            guard let jpegBase64 = originalImage.jpegData(compressionQuality: 0.8)?.base64EncodedString() else { return nil }
            return Photo(
                name: name,
                originalImage: originalImage,
                annotatedImage: originalImage,
                annotatedJPEGBase64: jpegBase64,
                navigablePoints: [],
                worldToCamera: nil,
                intrinsics: nil,
                position: nil,
                forward: nil,
                headingDegrees: nil
            )
        }

        /// Creates a `Photo` object annotated with navigable points.
        /// - Parameter name: A name for the photo (e.g. "photo001").
        /// - Parameter originalImage: The original image before annotation. For camera photos,
        /// this should be in portrait mode (rotated clockwise 90 degrees from the original camera
        /// image).
        /// - Parameter navigablePoints: Navigable points present in this image.
        /// - Parameter worldToCamera: Matrix transforming world-space points to camera-space
        /// for this image.
        /// - Parameter intrinsics: Camera intrinsic parameters, appropriately scaled for image
        /// resolution.
        /// - Parameter position: Position in world space the image was taken at (if this is a
        /// camera photo) or `nil` otherwise.
        /// - Parameter forward:Direction camera is pointing (photo direction), if applicable.
        /// - Parameter headingDegrees: Absolute heading in degrees that photo is oriented towards.
        /// - Returns: `Photo` object if successful else `nil`.
        static func createWithNavigablePointAnnotations(name: String, originalImage: UIImage, navigablePoints: [NavigablePoint], worldToCamera: Matrix4x4?, intrinsics: Matrix3x3?, position: Vector3?, forward: Vector3?, headingDegrees: Float?) -> Photo? {
            var jpegBase64: String?
            var annotatedImage: UIImage?

            if !navigablePoints.isEmpty,
               let worldToCamera = worldToCamera,
               let intrinsics = intrinsics {
                guard let annotatedPhoto = annotatePointNumbers(image: originalImage, with: navigablePoints, worldToCamera: worldToCamera, intrinsics: intrinsics, rotated: true) else { return nil }
                jpegBase64 = annotatedPhoto.jpegData(compressionQuality: 0.8)?.base64EncodedString()
                annotatedImage = annotatedPhoto
            } else {
                jpegBase64 = originalImage.jpegData(compressionQuality: 0.8)?.base64EncodedString()
                annotatedImage = originalImage
            }

            guard let jpegBase64 = jpegBase64,
                  let annotatedImage = annotatedImage else { return nil }

            return Photo(
                name: name,
                originalImage: originalImage,
                annotatedImage: annotatedImage,
                annotatedJPEGBase64: jpegBase64,
                navigablePoints: navigablePoints,
                worldToCamera: worldToCamera,
                intrinsics: intrinsics,
                position: position,
                forward: forward,
                headingDegrees: headingDegrees
            )
        }

        static func createWithHeadingAndDistanceAnnotations(name: String, originalImage: UIImage, worldToCamera: Matrix4x4?, intrinsics: Matrix3x3?, position: Vector3?, forward: Vector3?, headingDegrees: Float?) -> Photo? {
            var jpegBase64: String?
            var annotatedImage: UIImage?

            if let worldToCamera = worldToCamera,
               let intrinsics = intrinsics,
               let position = position,
               let forward = forward?.xzProjected.normalized,
               let headingDegrees = headingDegrees {
                let equidistantCurveByDistance = generateEquidistantCurves(
                    ourPosition: position,
                    ourForward: forward,
                    floorY: ARSessionManager.shared.floorY,
                    worldToCamera: worldToCamera,
                    intrinsics: intrinsics
                )
                let lineByDistance = generateRadialHeadingLines(
                    ourPosition: position,
                    ourHeading: headingDegrees,
                    floorY: ARSessionManager.shared.floorY,
                    worldToCamera: worldToCamera,
                    intrinsics: intrinsics
                )
                guard let distanceAnnotatedPhoto = annotateEquidistantCurves(image: originalImage, with: equidistantCurveByDistance, rotated: true) else { return nil }
                guard let headingAnnotatedPhoto = annotateRadialHeadingLines(image: distanceAnnotatedPhoto, with: lineByDistance, rotated: true) else { return nil }
                jpegBase64 = headingAnnotatedPhoto.jpegData(compressionQuality: 0.8)?.base64EncodedString()
                annotatedImage = headingAnnotatedPhoto
            }

            guard let jpegBase64 = jpegBase64,
                  let annotatedImage = annotatedImage else { return nil }

            return Photo(
                name: name,
                originalImage: originalImage,
                annotatedImage: annotatedImage,
                annotatedJPEGBase64: jpegBase64,
                navigablePoints: [],
                worldToCamera: worldToCamera,
                intrinsics: intrinsics,
                position: position,
                forward: forward,
                headingDegrees: headingDegrees
            )
        }

        /// Creates a `Photo` object annotated with path on the ground.
        /// - Parameter name: A name for the photo (e.g. "photo001").
        /// - Parameter originalImage: The original image before annotation. For camera photos,
        /// this should be in portrait mode (rotated clockwise 90 degrees from the original camera
        /// image).
        /// - Parameter path: Path in world points to draw.
        /// - Parameter worldToCamera: Matrix transforming world-space points to camera-space
        /// for this image.
        /// - Parameter intrinsics: Camera intrinsic parameters, appropriately scaled for image
        /// resolution.
        /// - Parameter position: Position in world space the image was taken at (if this is a
        /// camera photo) or `nil` otherwise.
        /// - Parameter forward:Direction camera is pointing (photo direction), if applicable.
        /// - Parameter headingDegrees: Absolute heading in degrees that photo is oriented towards.
        /// - Returns: `Photo` object if successful else `nil`.
        static func createWithPathAnnotations(name: String, originalImage: UIImage, path: [Vector3], worldToCamera: Matrix4x4?, intrinsics: Matrix3x3?, position: Vector3?, forward: Vector3?, headingDegrees: Float?) -> Photo? {
            var jpegBase64: String?
            var annotatedImage: UIImage?

            if !path.isEmpty,
               let position = position,
               let forward = forward,
               let worldToCamera = worldToCamera,
               let intrinsics = intrinsics {
                let imageSpacePathSegments = AnnotatingCamera.createImageSpacePathSegments(from: path, ourPosition: position, ourForward: forward, floorY: ARSessionManager.shared.floorY, worldToCamera: worldToCamera, intrinsics: intrinsics)
                guard let annotatedPhoto = annotatePath(image: originalImage, with: imageSpacePathSegments, rotated: true) else { return nil }
                jpegBase64 = annotatedPhoto.jpegData(compressionQuality: 0.8)?.base64EncodedString()
                annotatedImage = annotatedPhoto
            } else {
                jpegBase64 = originalImage.jpegData(compressionQuality: 0.8)?.base64EncodedString()
                annotatedImage = originalImage
            }

            guard let jpegBase64 = jpegBase64,
                  let annotatedImage = annotatedImage else { return nil }

            return Photo(
                name: name,
                originalImage: originalImage,
                annotatedImage: annotatedImage,
                annotatedJPEGBase64: jpegBase64,
                navigablePoints: [],
                worldToCamera: worldToCamera,
                intrinsics: intrinsics,
                position: position,
                forward: forward,
                headingDegrees: headingDegrees
            )
        }
    }

    struct NavigablePoint {
        let id: Int
        let cell: OccupancyMap.CellIndices
        let worldPoint: Vector3

        var textColor: UIColor {
            return UIColor.white
        }

        var backgroundColor: CGColor {
            return UIColor.black.cgColor
        }

        /// Image point with origin in lower-left (+y is up).
        func imagePoint(worldToCamera: Matrix4x4, intrinsics: Matrix3x3) -> CGPoint {
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
    }

    private var _imageID = 0
    private var _pointID = 0
    private var _occupancyMapIndexToID: [Int: Int] = [:]

    @MainActor
    func takePhoto(with annotation: Annotation = .navigablePoints) async -> Photo? {
        // Update occupancy
        _ = await NavigationController.shared.updateOccupancy()

        // Wait for next frame and acquire photo with necessary transforms for converting from world
        // -> image space
        guard let frame = try? await ARSessionManager.shared.nextFrame(),
              let cameraImage = getCameraImage(from: frame) else {
            return nil
        }
        let worldToCamera = frame.camera.transform.inverse

        // Return annotated photo
        return annotate(cameraImage: cameraImage, with: annotation, worldToCamera: worldToCamera)
    }

    private func annotate(cameraImage: (image: UIImage, intrinsics: Matrix3x3), with annotation: Annotation, worldToCamera: Matrix4x4) -> Photo? {
        // Photo needs to be rotated 90 degrees from landscale to portrait
        guard let rotatedPhoto = cameraImage.image.rotatedClockwise90() else { return nil }

        let ourPosition = ARSessionManager.shared.transform.position
        let ourHeading = ARSessionManager.shared.headingDegrees
        let ourForward = -ARSessionManager.shared.transform.forward

        switch annotation {
        case .navigablePoints:
            // Get navigable points
            let possibleNagivablePoints = generateProspectiveNavigablePoints(
                ourPosition: ourPosition,
                ourForward: ourForward,
                floorY: ARSessionManager.shared.floorY,
                occupancy: NavigationController.shared.occupancy,
                worldToCamera: worldToCamera,
                intrinsics: cameraImage.intrinsics,
                imageSize: cameraImage.image.size
            )
            let reachableNavigablePoints = excludeUnreachable(possibleNagivablePoints, ourPosition: ourPosition, occupancy: NavigationController.shared.occupancy)
            let navigablePoints = assignFinalIDs(reachableNavigablePoints)

            // Produce uniquely named photo object with annotations
            let name = "photo\(_imageID)"
            _imageID += 1
            return Photo.createWithNavigablePointAnnotations(
                name: name,
                originalImage: rotatedPhoto,
                navigablePoints: navigablePoints,
                worldToCamera: worldToCamera,
                intrinsics: cameraImage.intrinsics,
                position: ourPosition,
                forward: ourForward,
                headingDegrees: ourHeading
            )

        case .headingAndDistanceGuides:
            let name = "photo\(_imageID)"
            _imageID += 1
            return Photo.createWithHeadingAndDistanceAnnotations(
                name: name,
                originalImage: rotatedPhoto,
                worldToCamera: worldToCamera,
                intrinsics: cameraImage.intrinsics,
                position: ourPosition,
                forward: ourForward,
                headingDegrees: ourHeading
            )
        }
    }

    /// Generate a series of potential navigable points on the floor in front of the robot.
    /// - Parameter ourPosition: Robot current position in world space.
    /// - Parameter ourForward: Direction robot is facing.
    /// - Parameter floorY: Floor Y coordinate in world space. Navigable points placed on floor.
    /// - Parameter occupancy: Occupancy map, used to locate the cell indices of each point.
    /// - Parameter worldToCamera: Matrix transforming world-space points to camera-space
    /// for this image.
    /// - Parameter intrinsics: Camera intrinsic parameters, appropriately scaled for image
    /// resolution.
    /// - Parameter imageSize: Image size, for determining whether annotated points are actually
    /// inside the image.
    /// - Returns: Array of prospective navigable points. None are guaranteed to be reachable. The
    /// point IDs are based on their corresponding occupancy map cell's linear index. Take care to
    /// assign final indices before returning them.
    private func generateProspectiveNavigablePoints(ourPosition: Vector3, ourForward: Vector3, floorY: Float, occupancy: OccupancyMap, worldToCamera: Matrix4x4, intrinsics: Matrix3x3, imageSize: CGSize) -> [NavigablePoint] {
        // Generate a series of points on the floor, corresponding to occupancy map cells but
        // can be spaced more coarsely (every Nth cell). Those points that are within a given
        // angle and distance range of the current forward are used.

        let ourPosition = Vector3(x: ourPosition.x, y: floorY, z: ourPosition.z)
        let ourForward = ourForward.xzProjected.normalized

        var navigablePoints: [NavigablePoint] = []

        let spacing: Float = 0.75
        let cellSpacing = max(1, Int(spacing / occupancy.cellSide()))
        let searchRadiusCells = Int(4.0 / occupancy.cellSide()) // reasonable number of meters to search along each axis
        let ourCell = occupancy.positionToCell(ourPosition)
        let minCellX = ourCell.cellX - searchRadiusCells
        let maxCellX = ourCell.cellX + searchRadiusCells
        let minCellZ = ourCell.cellZ - searchRadiusCells
        let maxCellZ = ourCell.cellZ + searchRadiusCells

        var cellX = minCellX
        while cellX <= maxCellX {
            var cellZ = minCellZ
            while cellZ <= maxCellZ {
                let cell = OccupancyMap.CellIndices(cellX, cellZ)
                var worldPoint = occupancy.cellToPosition(cell)
                worldPoint.y = floorY   // need to be on floor to be rendered properly!
                let toPoint = (worldPoint - ourPosition).normalized

                // Is point in front of robot?
                if Vector3.dot(toPoint, ourForward) >= 0 {
                    // Is point within desired angle range on either side?
                    if Vector3.angle(toPoint, ourForward) <= 25 {
                        // Is point within desired distance range?
                        let distance = (worldPoint - ourPosition).xzProjected.magnitude
                        if /*distance >= (2 * spacing) && */distance <= (5 * spacing) {
                            // Create prospective navigable point
                            let id = occupancy.linearIndex(cell)
                            let point = NavigablePoint(id: id, cell: cell, worldPoint: worldPoint)

                            // Final check: ensure projected point is on-screen
                            let imagePoint = point.imagePoint(worldToCamera: worldToCamera, intrinsics: intrinsics)
                            if imagePoint.x >= 0 && imagePoint.x < imageSize.width && imagePoint.y >= 0 && imagePoint.y < imageSize.height {
                                navigablePoints.append(point)
                            }
                        }
                    }
                }
                cellZ += cellSpacing
            }
            cellX += cellSpacing
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

    /// Given a set of navigable points with IDs set based on their occupancy map index, remaps
    /// the IDs to be contiguous and packed. This compresses the range of numbers when performed
    /// after any sort of filtering. IDs cannot be reused.
    private func assignFinalIDs(_ points: [NavigablePoint]) -> [NavigablePoint] {
        var relabeledPoints: [NavigablePoint] = []

        for point in points {
            var id = 0

            let index = point.id
            if let existingID = _occupancyMapIndexToID[index] {
                // This point has already been mapped
                id = existingID
            } else {
                // Haven't seen this one before, assign the next ID to it
                id = _pointID
                _pointID += 1
                _occupancyMapIndexToID[index] = id
            }

            relabeledPoints.append(NavigablePoint(id: id, cell: point.cell, worldPoint: point.worldPoint))
        }

        return relabeledPoints
    }

    /// Generates a series of curves for different distances. Each image-space point along a curve
    /// is the same distance from the current position.
    /// - Parameter ourPosition: Robot current position in world space.
    /// - Parameter ourForward: Direction robot is facing.
    /// - Parameter floorY: Floor Y value of robot. All curves are rendered at floor level.
    /// - Parameter worldToCamera:Inverse camera transform matrix (i.e., world to camera-local space).
    /// - Parameter intrinsics:Camera intrinsics. Used with `worldToCamera`to convert world-space
    /// points to image-space annotations.
    /// - Returns: Dictionary where the keys are distance (meters) and the values are image-space
    /// points at that distance.
    private static func generateEquidistantCurves(ourPosition: Vector3, ourForward: Vector3, floorY: Float, worldToCamera: Matrix4x4, intrinsics: Matrix3x3) -> [Float: [CGPoint]] {
        // Generate the world points to form an equidistant curve in front of the camera
        let ourPosition = Vector3(x: ourPosition.x, y: floorY, z: ourPosition.z)
        var worldPointsByDistance: [Float: [Vector3]] = [:]
        for distance in Array<Float>([ 0.75, 1.00, 1.50, 2.25, 3.25 ]) {
            let halfAngle: Float = 40
            let numSteps: Float = 300
            worldPointsByDistance[distance] = []
            for degrees in stride(from: -halfAngle, to: halfAngle, by: 2 * halfAngle / numSteps) {
                let forward = ourForward.rotated(by: degrees, about: .up)
                let worldPoint = ourPosition + forward * distance
                var worldPoints = worldPointsByDistance[distance]!
                worldPoints.append(worldPoint)
                worldPointsByDistance[distance] = worldPoints
            }
        }

        // Convert to CGPoints in image space
        var curveByDistance: [Float: [CGPoint]] = [:]
        for (distance, worldPoints) in worldPointsByDistance {
            let imagePoints = worldPoints.map { (worldPoint: Vector3) in
                // To view space
                var cameraPoint = worldToCamera.transformPoint(worldPoint)
                cameraPoint.y *= -1
                cameraPoint.z *= -1

                // Project onto the 2D frame where the origin is in the upper-left and +y is down
                let homogeneous = Vector3(x: cameraPoint.x / cameraPoint.z, y: cameraPoint.y / cameraPoint.z, z: 1)
                let projected = intrinsics * homogeneous
                return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
            }
            curveByDistance[distance] = imagePoints
        }

        return curveByDistance
    }

    /// Generates a series of lines at different absolute headings, represented as points in image
    /// space.
    /// - Parameter ourPosition: Robot current position in world space.
    /// - Parameter ourHeading: Absolute heading (degrees) that the robot is facing.
    /// - Parameter floorY: Floor Y value of robot. All curves are rendered at floor level.
    /// - Parameter worldToCamera:Inverse camera transform matrix (i.e., world to camera-local space).
    /// - Parameter intrinsics:Camera intrinsics. Used with `worldToCamera`to convert world-space
    /// points to image-space annotations.
    /// - Returns: Dictionary where the keys are heading (degrees) and the values are image-space
    /// points creating a line along that direction.
    private static func generateRadialHeadingLines(ourPosition: Vector3, ourHeading: Float, floorY: Float, worldToCamera: Matrix4x4, intrinsics: Matrix3x3) -> [Float: [CGPoint]] {
        // Generate world points radiating outwards along different headings
        let ourPosition = Vector3(x: ourPosition.x, y: floorY, z: ourPosition.z)
        var worldPointsByHeading: [Float: [Vector3]] = [:]
        for deltaDegrees in Array<Float>([ -20, -10, 0, 10, 20 ]) {
            // Compute absolute heading and constrain it to [0,360)
            let headingDegrees = (ourHeading + deltaDegrees) >= 0 ? ((ourHeading + deltaDegrees).truncatingRemainder(dividingBy: 360)) : ((ourHeading + deltaDegrees) + 360)
            let forward = ARSessionManager.shared.direction(fromDegrees: headingDegrees)

            // Generate points in world space along the heading
            let maxDistance: Float = 3.25
            let numSteps: Float = 50
            var worldPoints: [Vector3] = []
            for distance in stride(from: 0, to: maxDistance, by: maxDistance / numSteps) {
                worldPoints.append(ourPosition + forward * distance)
            }
            worldPointsByHeading[headingDegrees] = worldPoints
        }

        // Convert to CGPoints in image space
        var lineByHeading: [Float: [CGPoint]] = [:]
        for (headingDegrees, worldPoints) in worldPointsByHeading {
            let imagePoints = worldPoints.map { (worldPoint: Vector3) in
                // To view space
                var cameraPoint = worldToCamera.transformPoint(worldPoint)
                cameraPoint.y *= -1
                cameraPoint.z *= -1

                // Project onto the 2D frame where the origin is in the upper-left and +y is down
                let homogeneous = Vector3(x: cameraPoint.x / cameraPoint.z, y: cameraPoint.y / cameraPoint.z, z: 1)
                let projected = intrinsics * homogeneous
                return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
            }
            lineByHeading[headingDegrees] = imagePoints
        }

        return lineByHeading
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
    /// Point numbers are rendered.
    /// - Parameter image: The image to annotate.
    /// - Parameter points: Points to annotate.
    /// - Parameter worldToCamera:Inverse camera transform matrix (i.e., world to camera-local space).
    /// - Parameter intrinsics:Camera intrinsics. Used with `worldToCamera`to convert world-space
    /// points to image-space annotations.
    /// - Parameter rotated: If `true`, the image is rotated clockwise 90 degrees relative to how
    /// the points are specified. The points will be adjusted accordingly.
    /// - Returns: New image with annotations or `nil` if anything went wrong.
    private static func annotatePointNumbers(image: UIImage, with points: [NavigablePoint], worldToCamera: Matrix4x4, intrinsics: Matrix3x3, rotated: Bool) -> UIImage? {
        let sideLengthAt640Height = CGFloat(20)
        let sideLength = CGFloat(image.size.height / 640.0) * sideLengthAt640Height

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
            let imagePoint = point.imagePoint(worldToCamera: worldToCamera, intrinsics: intrinsics)
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

    /// Renders equidistant curve annotations on the image (curves whose points are all the same
    /// distance from the position the photo was taken at). Necessary adjustments are made if the
    /// image has been rotated into a portrait orientation. Distance labels are rendered.
    /// - Parameter image: The image to annotate.
    /// - Parameter equidistantCurveByDistance: Curves to draw. A dictionary with the key being distance and the value
    /// being an array of points in image space.
    /// - Parameter rotated: If `true`, the image is rotated clockwise 90 degrees relative to how
    /// the points are specified. The points will be adjusted accordingly.
    /// - Returns: New image with annotations or `nil` if anything went wrong.
    private static func annotateEquidistantCurves(image: UIImage, with equidistantCurveByDistance: [Float: [CGPoint]], rotated: Bool) -> UIImage? {
        let sideLengthAt640Height = CGFloat(32)
        let sideLength = CGFloat(image.size.height / 640.0) * sideLengthAt640Height

        // Get the image size
        let imageSize = image.size
        let scale = image.scale

        // Draw original image
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        image.draw(in: CGRect(origin: .zero, size: imageSize))

        // Draw curves and label them with distance
        for (distance, curve) in equidistantCurveByDistance {
            // Draw the curve
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2.0)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            var moved = false
            var points: [CGPoint] = []
            for imagePoint in curve {
                // Get (x,y) and adjust for rotation if need be
                let x = rotated ? (imageSize.width - imagePoint.y) : imagePoint.x
                let y = rotated ? imagePoint.x : imagePoint.y
                let point = CGPoint(x: x, y: y)

                // Line
                if !moved {
                    context.move(to: point)
                    moved = true
                } else {
                    context.addLine(to: point)
                }

                // Retain points that are visible
                if point.x >= 0 && point.x < imageSize.width && point.y >= 0 && point.y < imageSize.height {
                    points.append(point)
                }
            }
            context.strokePath()

            // If no points (e.g., camera pointed too far up off the floor to capture the curve),
            // skip
            if points.isEmpty {
                continue
            }

            // Sort points left to right in image space
            points = points.sorted(by: { $0.x < $1.x })

            // Compute the text size
            let text = String(format: "%1.2f m", distance)
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: sideLength / 2, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: textAttributes)

            // Draw the background square
            let x = points[0].x
            let y = points[0].y
            context.setFillColor(UIColor.black.cgColor)
            let backgroundRect = CGRect(x: x, y: y, width: textSize.width, height: textSize.height)
            context.fill(backgroundRect)

            // Print distance
            let textRect = CGRect(x: x, y: y, width: textSize.width, height: textSize.height)
            text.draw(in: textRect, withAttributes: textAttributes)
        }

        // Return new image
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }

    /// Renders radial heading lines on the image. Necessary adjustments are made if the image has
    /// been rotated into a portrait orientation. Each line is labeled by the degrees.
    /// - Parameter image: The image to annotate.
    /// - Parameter lineByHeading: Lines to draw. A dictionary with the key being heading (degrees) and the
    /// value being an array of points in image space.
    /// - Parameter rotated: If `true`, the image is rotated clockwise 90 degrees relative to how
    /// the points are specified. The points will be adjusted accordingly.
    /// - Returns: New image with annotations or `nil` if anything went wrong.
    private static func annotateRadialHeadingLines(image: UIImage, with lineByHeading: [Float: [CGPoint]], rotated: Bool) -> UIImage? {
        let sideLengthAt640Height = CGFloat(26)
        let sideLength = CGFloat(image.size.height / 640.0) * sideLengthAt640Height

        // Get the image size
        let imageSize = image.size
        let scale = image.scale

        // Draw original image
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        image.draw(in: CGRect(origin: .zero, size: imageSize))

        // Draw curves and label them with distance
        for (headingDegrees, linePoints) in lineByHeading {
            // Draw the line
            context.setStrokeColor(UIColor.magenta.cgColor)
            context.setLineWidth(2.0)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            var moved = false
            var points: [CGPoint] = []
            for imagePoint in linePoints {
                // Get (x,y) and adjust for rotation if need be
                let x = rotated ? (imageSize.width - imagePoint.y) : imagePoint.x
                let y = rotated ? imagePoint.x : imagePoint.y
                let point = CGPoint(x: x, y: y)

                // Line
                if !moved {
                    context.move(to: point)
                    moved = true
                } else {
                    context.addLine(to: point)
                }

                // Retain points that are visible
                if point.x >= 0 && point.x < imageSize.width && point.y >= 0 && point.y < imageSize.height {
                    points.append(point)
                }
            }
            context.strokePath()

            // If no points (e.g., camera pointed too far up off the floor to capture the curve),
            // skip
            if points.isEmpty {
                continue
            }

            // Sort points bottom to top in image space
            points = points.sorted(by: { $0.y > $1.y })

            // Compute the text size
            let text = String(format: "%1.0f deg", headingDegrees)
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: sideLength / 2, weight: .bold),
                .foregroundColor: UIColor.magenta
            ]
            let textSize = text.size(withAttributes: textAttributes)

            // Draw the background square centered on the bottom of the line
            let x = points[0].x
            let y = points[0].y
            context.setFillColor(UIColor.black.cgColor)
            let backgroundRect = CGRect(x: x - textSize.width / 2, y: y - textSize.height, width: textSize.width, height: textSize.height)
            context.fill(backgroundRect)

            // Print degree marker
            let textRect = CGRect(x: x - textSize.width / 2, y: y - textSize.height, width: textSize.width, height: textSize.height)
            text.draw(in: textRect, withAttributes: textAttributes)
        }

        // Return new image
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }

    /// Renders path.
    /// - Parameter image: The image to annotate.
    /// - Parameter pathSegments: Path points in image space as a series of contiguous segments.
    /// - Parameter rotated: If `true`, the image is rotated clockwise 90 degrees relative to how
    /// the points are specified. The points will be adjusted accordingly.
    /// - Returns: New image with annotations or `nil` if anything went wrong.
    private static func annotatePath(image: UIImage, with pathSegments: [[CGPoint]], rotated: Bool) -> UIImage? {
        if pathSegments.isEmpty {
            return image
        }

        // Get the image size
        let imageSize = image.size
        let scale = image.scale

        // Draw original image
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        image.draw(in: CGRect(origin: .zero, size: imageSize))

        // Draw lines
        context.setStrokeColor(UIColor.cyan.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(50.0)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for path in pathSegments {
            if path.isEmpty {
                continue
            }

            // Draw this path semgent
            context.move(to: path.first!)
            for i in 1..<path.count {
                // Get (x,y) and adjust for rotation if need be
                let imagePoint = path[i]
                let x = rotated ? (imageSize.width - imagePoint.y) : imagePoint.x
                let y = rotated ? imagePoint.x : imagePoint.y
                let point = CGPoint(x: x, y: y)

                // Line
                context.addLine(to: point)
            }

            // Draw the line
            context.strokePath()
        }

        // Return new image
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }

    /// Given a world-space path, chops it up into tiny increments and tests each point against the
    /// current view to create a series of paths that should be visible in the image. A very crude
    /// form of clipping.
    private static func createImageSpacePathSegments(from path: [Vector3], ourPosition: Vector3, ourForward: Vector3, floorY: Float, worldToCamera: Matrix4x4, intrinsics: Matrix3x3) -> [[CGPoint]] {
        if path.count <= 1 {
            return []
        }

        // Chop up into fine steps
        let stepSize: Float = 0.05
        var finePath: [Vector3] = []
        for i in 0..<(path.count - 1) {
            let p0 = Vector3(x: path[i].x, y: floorY, z: path[i].z)
            let p1 = Vector3(x: path[i + 1].x, y: floorY, z: path[i + 1].z)
            let dir = (p1 - p0).normalized
            let length = (p1 - p0).magnitude
            let numSteps = Int(ceil(length / stepSize))
            let step = length / Float(numSteps)
            for j in 0..<numSteps {
                finePath.append(p0 + Float(j) * step * dir)
            }
        }

        // Create a series of on-screen segments by testing the world points to ensure they
        // are in front of camera. Whenever a point falls off screen, we terminate the
        // current path and begin a new segment.
        var pathSegments: [[Vector3]] = []
        var currentSegment: [Vector3] = []
        for i in 0..<finePath.count {
            let worldPoint = finePath[i]
            let inFrontOfCamera = Vector3.dot(ourForward, worldPoint - ourPosition) >= 0
            if inFrontOfCamera {
                currentSegment.append(worldPoint)
            } else {
                // Point is off-screen, end current segment
                if !currentSegment.isEmpty {
                    pathSegments.append(currentSegment)
                    currentSegment = []
                }
            }
        }

        if !currentSegment.isEmpty {
            pathSegments.append(currentSegment)
        }

        // Return everything in image space
        return pathSegments.map { $0.map { Self.imagePoint(worldPoint: $0, worldToCamera: worldToCamera, intrinsics: intrinsics) } }
    }

    /// Image point with origin in lower-left (+y is up).
    private static func imagePoint(worldPoint: Vector3, worldToCamera: Matrix4x4, intrinsics: Matrix3x3) -> CGPoint {
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
}
