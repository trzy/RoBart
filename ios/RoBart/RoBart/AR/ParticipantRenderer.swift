//
//  ParticipantRenderer.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//

import ARKit
import RealityKit

/// Renders participant anchors.
class ParticipantRenderer {
    private var _entityByAnchorID: [UUID: AnchorEntity] = [:]

    var participantCount: Int {
        return _entityByAnchorID.count
    }

    func addParticipants(from anchors: [ARAnchor], to arView: ARView) {
#if !targetEnvironment(simulator)
        for anchor in anchors {
            if let participantAnchor = anchor as? ARParticipantAnchor {
                let entity = AnchorEntity(anchor: participantAnchor)
                entity.addChild(createXYZGizmo())
                _entityByAnchorID[anchor.identifier] = entity
                arView.scene.addAnchor(entity)
            }
        }
#endif
    }

    func removeParticipants(for anchors: [ARAnchor]) {
        for anchor in anchors {
            if let entity = _entityByAnchorID.removeValue(forKey: anchor.identifier) {
                entity.removeFromParent()
            }
        }
    }

#if !targetEnvironment(simulator)
    private func createLine(length: Float, color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: [0.01, 0.01, length])
        let material = SimpleMaterial(color: color, isMetallic: false)
        let line = ModelEntity(mesh: mesh, materials: [material])
        return line
    }

    private func createXYZGizmo(length: Float = 0.1, thickness: Float = 2.0) -> Entity {
        let thicknessInM = (length / 100) * thickness
        let cornerRadius = thickness / 2.0
        let offset = length / 2.0

        let xAxisBox = MeshResource.generateBox(size: [length, thicknessInM, thicknessInM], cornerRadius: cornerRadius)
        let yAxisBox = MeshResource.generateBox(size: [thicknessInM, length, thicknessInM], cornerRadius: cornerRadius)
        let zAxisBox = MeshResource.generateBox(size: [thicknessInM, thicknessInM, length], cornerRadius: cornerRadius)

        let xAxis = ModelEntity(mesh: xAxisBox, materials: [UnlitMaterial(color: .red)])
        let yAxis = ModelEntity(mesh: yAxisBox, materials: [UnlitMaterial(color: .green)])
        let zAxis = ModelEntity(mesh: zAxisBox, materials: [UnlitMaterial(color: .blue)])

        xAxis.position = [offset, 0, 0]
        yAxis.position = [0, offset, 0]
        zAxis.position = [0, 0, offset]

        let gizmo = Entity()
        gizmo.addChild(xAxis)
        gizmo.addChild(yAxis)
        gizmo.addChild(zAxis)
        return gizmo
    }
#endif
}
