//
//  SceneMeshRenderer.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import ARKit
import RealityKit

/// Renders anchor geometry.
class SceneMeshRenderer {
    private var _entityByAnchorID: [UUID: AnchorEntity] = [:]

    func addMesh(from anchor: ARAnchor, to arView: ARView) {
        var entity: AnchorEntity?

        switch anchor {
        case let planeAnchor as ARPlaneAnchor:
            guard let mesh = tryCreatePlaneMesh(from: planeAnchor) else { return }
            //entity = createEntity(anchoredTo: anchor, with: mesh)
        default:
            break
        }

        if let entity = entity {
            _entityByAnchorID[anchor.identifier] = entity
            arView.scene.addAnchor(entity)
        }
    }

    func addMeshes(from anchors: [ARAnchor], to arView: ARView) {
        for anchor in anchors {
            addMesh(from: anchor, to: arView)
        }
    }

    func updateMesh(from anchor: ARAnchor) {
        guard let entity = _entityByAnchorID[anchor.identifier] else { return }
        guard let modelEntity = entity.children[0] as? ModelEntity else { return }

        switch anchor {
        case let planeAnchor as ARPlaneAnchor:
            guard let mesh = tryCreatePlaneMesh(from: planeAnchor) else { return }
            modelEntity.model?.mesh = mesh
        default:
            break
        }
    }

    func updateMeshes(from anchors: [ARAnchor]) {
        for anchor in anchors {
            updateMesh(from: anchor)
        }
    }

    func removeMesh(for anchor: ARAnchor) {
        if let entity = _entityByAnchorID.removeValue(forKey: anchor.identifier) {
            entity.removeFromParent()
        }
    }

    func removeMeshes(for anchors: [ARAnchor]) {
        for anchor in anchors {
            removeMesh(for: anchor)
        }
    }

    private func tryCreatePlaneMesh(from anchor: ARPlaneAnchor) -> MeshResource? {
        var descriptor = MeshDescriptor(name: "Plane")
        descriptor.positions = MeshBuffer(anchor.geometry.vertices)
        descriptor.primitives = .triangles(anchor.geometry.triangleIndices.map { UInt32($0) })
        return try? MeshResource.generate(from: [ descriptor ])
    }

//    private func createEntity(anchoredTo anchor: ARAnchor, with mesh: MeshResource) -> AnchorEntity {
//        let color = UIColor(cgColor: CGColor(red: 0, green: 1, blue: 1, alpha: 0.8))
//        let entity = ModelEntity(mesh: mesh, materials: [ SimpleMaterial(color: color, roughness: 1.0, isMetallic: false) ])
//        let anchorEntity = AnchorEntity(anchor: anchor)
//        anchorEntity.addChild(entity)
//        return anchorEntity
//    }
}
