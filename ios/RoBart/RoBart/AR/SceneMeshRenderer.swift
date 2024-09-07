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
    private var _entityByAnchorID: [UUID: Entity] = [:]
    private var _planeRootEntity: Entity?
    private var _worldMeshRootEntity: Entity?
    private let _planeColor = UIColor(cgColor: CGColor(red: 0, green: 1, blue: 1, alpha: 0.6))
    private let _worldMeshColor = UIColor(cgColor: CGColor(red: 1, green: 0, blue: 1, alpha: 0.7))

    var renderPlanes = false {
        didSet {
            _planeRootEntity?.isEnabled = renderPlanes
        }
    }

    var renderWorldMeshes = false {
        didSet {
            _worldMeshRootEntity?.isEnabled = renderWorldMeshes
        }
    }

    func addMesh(from anchor: ARAnchor, to arView: ARView) {
        let planeRootEntity = getPlaneRootEntity(scene: arView.scene)
        let worldMeshRootEntity = getWorldMeshRootEntity(scene: arView.scene)

        var entity: Entity?

        switch anchor {
        case let planeAnchor as ARPlaneAnchor:
#if !targetEnvironment(simulator)
            guard let mesh = tryCreatePlaneMesh(from: planeAnchor) else { break }
            entity = createEntity(anchoredTo: anchor, with: mesh, color: _planeColor)
            planeRootEntity.addChild(entity!)
#endif
            break
        case let meshAnchor as ARMeshAnchor:
#if !targetEnvironment(simulator)
            guard let mesh = tryCreateWorldMesh(from: meshAnchor) else { break }
            entity = createUnanchoredEntity(anchoredTo: anchor, with: mesh, color: _worldMeshColor)
            worldMeshRootEntity.addChild(entity!)
#endif
            break
        default:
            break
        }

        if let entity = entity {
            _entityByAnchorID[anchor.identifier] = entity
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
            guard let mesh = tryCreatePlaneMesh(from: planeAnchor) else { break }
            modelEntity.model?.mesh = mesh
        case let meshAnchor as ARMeshAnchor:
            guard let mesh = tryCreateWorldMesh(from: meshAnchor) else { break }
            modelEntity.model?.mesh = mesh
            entity.transform.matrix = anchor.transform  // because entity is not a real AnchorEntity
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

    private func tryCreateWorldMesh(from anchor: ARMeshAnchor) -> MeshResource? {
        // Read out triangles
        assert(anchor.geometry.faces.primitiveType == .triangle)
        let numFaces = anchor.geometry.faces.count
        let numIndices = numFaces * 3
        var triangles = [UInt32](repeating: 0, count: numIndices)
        anchor.geometry.faces.buffer.contents().withMemoryRebound(to: UInt32.self, capacity: numIndices) {
            for i in 0..<numIndices {
                triangles[i] = $0[i]
            }
        }

        // Read out vertices
        assert(anchor.geometry.vertices.componentsPerVector == 3)
        assert(anchor.geometry.vertices.format == .float3)
        assert(anchor.geometry.vertices.offset == 0)
        assert(anchor.geometry.vertices.stride == 3 * 4)
        assert(anchor.geometry.vertices.componentsPerVector == 3)
        let numVerts = anchor.geometry.vertices.count
        let numFloats = numVerts * 3
        var vertices = [Vector3](repeating: .zero, count: numVerts)
        anchor.geometry.vertices.buffer.contents().withMemoryRebound(to: Float.self, capacity: numFloats) {
            var i = 0
            while i < numFloats {
                vertices[i/3] = Vector3(x: $0[i+0], y: $0[i+1], z: $0[i+2])
                i += 3
            }
        }

        // Generate mesh
        var descriptor = MeshDescriptor(name: "WorldMesh")
        descriptor.positions = MeshBuffer(vertices)
        descriptor.primitives = .triangles(triangles)

        return try? MeshResource.generate(from: [descriptor])
    }

#if !targetEnvironment(simulator)   // fails on simulator because one of the classes used here is apparently not present in simulator builds
    private func createEntity(anchoredTo anchor: ARAnchor, with mesh: MeshResource, color: UIColor) -> AnchorEntity {
        let entity = ModelEntity(mesh: mesh, materials: [ SimpleMaterial(color: color, roughness: 1.0, isMetallic: false) ])
        let anchorEntity = AnchorEntity(anchor: anchor)
        anchorEntity.addChild(entity)
        return anchorEntity
    }

    /// For some reason, we cannot use the procedure in createEntity() above (attaching the
    /// ModelEntity to the AnchorEntity). Instead, we need to create a free-floating entity and
    /// continuously update its transform.
    private func createUnanchoredEntity(anchoredTo anchor: ARAnchor, with mesh: MeshResource, color: UIColor) -> Entity {
        let fakeAnchorEntity = Entity()
        let entity = ModelEntity(mesh: mesh, materials: [ SimpleMaterial(color: color, roughness: 1.0, isMetallic: false) ])
        fakeAnchorEntity.transform.matrix = anchor.transform
        fakeAnchorEntity.addChild(entity)
        return fakeAnchorEntity
    }
#endif

    private func getPlaneRootEntity(scene: Scene) -> Entity {
        if _planeRootEntity == nil {
            let entity = AnchorEntity()
            _planeRootEntity = entity
            scene.addAnchor(entity)
        }
        _planeRootEntity!.isEnabled = renderPlanes
        return _planeRootEntity!
    }

    private func getWorldMeshRootEntity(scene: Scene) -> Entity {
        if _worldMeshRootEntity == nil {
            let entity = AnchorEntity()
            _worldMeshRootEntity = entity
            scene.addAnchor(entity)
        }
        _worldMeshRootEntity!.isEnabled = renderWorldMeshes
        return _worldMeshRootEntity!
    }
}
