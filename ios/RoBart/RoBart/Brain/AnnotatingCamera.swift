//
//  AnnotatingCamera.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/18/24.
//
//  Takes a photo (of the robot's current view) and adds annotations for the AI to analyze.
//

import ARKit
import UIKit

class AnnotatingCamera {
    enum Annotation {
        case navigablePoints
        case headingAndDistanceGuides
    }

    struct Photo {
        let name: String
        let jpegBase64: String
        let navigablePoints: [NavigablePoint]
        let position: Vector3?
        let headingDegrees: Float?
    }

    struct NavigablePoint {
        let id: Int
        let cell: OccupancyMap.CellIndices
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
        let ourForward = -ARSessionManager.shared.transform.forward.xzProjected.normalized

        switch annotation {
        case .navigablePoints:
            // Get navigable points
            let possibleNagivablePoints = generateProspectiveNavigablePoints(
                ourPosition: ourPosition,
                ourForward: ourForward,
                floorY: ARSessionManager.shared.floorY,
                worldToCamera: worldToCamera,
                intrinsics: cameraImage.intrinsics,
                occupancy: NavigationController.shared.occupancy
            )
            let reachableNavigablePoints = excludeUnreachable(possibleNagivablePoints, ourPosition: ourPosition, occupancy: NavigationController.shared.occupancy)
            let navigablePoints = assignFinalIDs(reachableNavigablePoints)

            // Annotate image
            guard let annotatedPhoto = annotatePointNumbers(image: rotatedPhoto, with: navigablePoints, rotated: true) else { return nil }

            // Get JPEG
            guard let jpegBase64 = annotatedPhoto.jpegData(compressionQuality: 0.8)?.base64EncodedString() else { return nil }

            // Produce uniquely named photo object
            let name = "photo\(_imageID)"
            _imageID += 1
            return Photo(name: name, jpegBase64: jpegBase64, navigablePoints: navigablePoints, position: ourPosition, headingDegrees: ourHeading)

        case .headingAndDistanceGuides:
            let equidistantCurveByDistance = generateEquidistantCurves(
                ourPosition: ourPosition,
                ourForward: ourForward,
                floorY: ARSessionManager.shared.floorY,
                worldToCamera: worldToCamera,
                intrinsics: cameraImage.intrinsics
            )
            let lineByDistance = generateRadialHeadingLines(
                ourPosition: ourPosition,
                ourHeading: ourHeading,
                floorY: ARSessionManager.shared.floorY,
                worldToCamera: worldToCamera,
                intrinsics: cameraImage.intrinsics
            )
            guard let distanceAnnotatedPhoto = annotateEquidistantCurves(image: rotatedPhoto, with: equidistantCurveByDistance, rotated: true) else { return nil }
            guard let headingAnnotatedPhoto = annotateRadialHeadingLines(image: distanceAnnotatedPhoto, with: lineByDistance, rotated: true) else { return nil }
            guard let jpegBase64 = headingAnnotatedPhoto.jpegData(compressionQuality: 0.8)?.base64EncodedString() else { return nil }
            let name = "photo\(_imageID)"
            _imageID += 1
            return Photo(name: name, jpegBase64: jpegBase64, navigablePoints: [], position: ourPosition, headingDegrees: ourHeading)
        }
    }

    /// Generate a series of potential navigable points on the floor in front of the robot.
    /// - Parameter ourPosition: Robot current position in world space.
    /// - Parameter ourForward: Direction robot is facing.
    /// - Parameter floorY: Floor Y coordinate in world space. Navigable points placed on floor.
    /// - Parameter worldToCamera: Inverse camera transform matrix (i.e., world to camera-local space).
    /// - Parameter intrinsics: Camera intrinsics. Used with `worldToCamera`to convert world-space
    /// points to image-space annotations.
    /// - Parameter occupancy: Occupancy map, used to locate the cell indices of each point.
    /// - Returns: Array of prospective navigable points. None are guaranteed to be reachable. The
    /// point IDs are based on their corresponding occupancy map cell's linear index. Take care to
    /// assign final indices before returning them.
    private func generateProspectiveNavigablePoints(ourPosition: Vector3, ourForward: Vector3, floorY: Float, worldToCamera: Matrix4x4, intrinsics: Matrix3x3, occupancy: OccupancyMap) -> [NavigablePoint] {
        // Generate a series of points on the floor, corresponding to occupancy map cells but
        // can be spaced more coarsely (every Nth cell). Those points that are within a given
        // angle and distance range of the current forward are used.

        let ourPosition = Vector3(x: ourPosition.x, y: floorY, z: ourPosition.z)
        let ourForward = ourForward.xzProjected.normalized

        var navigablePoints: [NavigablePoint] = []

        let spacing: Float = 0.75
        let cellSpacing = max(1, Int(spacing / occupancy.cellSide()))
        let searchRadiusCells = Int(4.0 / occupancy.cellSide())
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
                            // Create navigable point
                            let id = occupancy.linearIndex(cell)
                            navigablePoints.append(NavigablePoint(id: id, cell: cell, worldPoint: worldPoint, worldToCamera: worldToCamera, intrinsics: intrinsics))
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

            relabeledPoints.append(NavigablePoint(id: id, cell: point.cell, worldPoint: point.worldPoint, worldToCamera: point.worldToCamera, intrinsics: point.intrinsics))
        }

        return relabeledPoints
    }

    private func generateEquidistantCurves(ourPosition: Vector3, ourForward: Vector3, floorY: Float, worldToCamera: Matrix4x4, intrinsics: Matrix3x3) -> [Float: [CGPoint]] {
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

    private func generateRadialHeadingLines(ourPosition: Vector3, ourHeading: Float, floorY: Float, worldToCamera: Matrix4x4, intrinsics: Matrix3x3) -> [Float: [CGPoint]] {
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

    /// Renders navigable points as cell indexc annotations on the image (rectangles with numbers
    /// inside of them). Necessary adjustments are made if the image has been rotated into a
    /// portrait orientation.
    /// - Parameter image: The image to annotate.
    /// - Parameter with: Points to annotate.
    /// - Parameter rotated: If `true`, the image is rotated clockwise 90 degrees relative to how
    /// the points are specified. The points will be adjusted accordingly.
    /// - Returns: New image with annotations or `nil` if anything went wrong.
    private func annotateCells(image: UIImage, with points: [NavigablePoint], rotated: Bool) -> UIImage? {
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
            // Compute the text size
            let text = String(format: "%d,%d", point.cell.cellX, point.cell.cellZ)
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: sideLength / 2, weight: .bold),
                .foregroundColor: point.textColor
            ]
            let textSize = text.size(withAttributes: textAttributes)

            // Draw the background square. Note that when rotating image clockwise and using an
            // upper-left origin with +y as down, it is necessary to invert x (because +y in the
            // original image moves down but rotated clockwise, that direction is -x instead of
            // +x).
            let imagePoint = point.imagePoint
            let x = rotated ? (imageSize.width - imagePoint.y) : imagePoint.x
            let y = rotated ? imagePoint.x : imagePoint.y
            context.setFillColor(point.backgroundColor)
            let backgroundRect = CGRect(x: x - textSize.width / 2, y: y - textSize.height / 2, width: textSize.width, height: textSize.height)
            context.fill(backgroundRect)

            // Print cell
            let textX = x - textSize.width / 2
            let textY = y - textSize.height / 2
            let textRect = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)
            text.draw(in: textRect, withAttributes: textAttributes)
        }

        // Return new image
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }

    /// Renders navigable points as annotations on the image (squares with numbers inside of them).
    /// Necessary adjustments are made if the image has been rotated into a portrait orientation.
    /// Point numbers are rendered.
    /// - Parameter image: The image to annotate.
    /// - Parameter with: Points to annotate.
    /// - Parameter rotated: If `true`, the image is rotated clockwise 90 degrees relative to how
    /// the points are specified. The points will be adjusted accordingly.
    /// - Returns: New image with annotations or `nil` if anything went wrong.
    private func annotatePointNumbers(image: UIImage, with points: [NavigablePoint], rotated: Bool) -> UIImage? {
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

    private func annotateEquidistantCurves(image: UIImage, with equidistantCurveByDistance: [Float: [CGPoint]], rotated: Bool) -> UIImage? {
        let sideLength = CGFloat(32)

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

    private func annotateRadialHeadingLines(image: UIImage, with lineByHeading: [Float: [CGPoint]], rotated: Bool) -> UIImage? {
        let sideLength = CGFloat(26)

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
}
