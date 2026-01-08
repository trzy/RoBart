//
//  ParticipantRenderer.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
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
