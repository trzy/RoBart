//
//  FollowPerson.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/23/24.
//

import ARKit
import CoreGraphics
import CoreImage
import RealityKit
import Vision
import UIKit

@MainActor
func followPerson() async {
    let anchor = AnchorEntity(world: .zero)
    let sphere = MeshResource.generateSphere(radius: 0.1)
    let model = ModelEntity(mesh: sphere, materials: [ SimpleMaterial(color: UIColor.purple, roughness: 1.0, isMetallic: false) ])
    anchor.addChild(model)
    while true {
        guard let scene = ARSessionManager.shared.scene else {
            try? await Task.sleep(for: .milliseconds(16))
            continue
        }
        scene.addAnchor(anchor)
        break
    }

    while true {
        guard let frame = try? await ARSessionManager.shared.nextFrame() else {
            try? await Task.sleep(for: .milliseconds(32))
            continue
        }

        let people = detectHumans(in: frame)
        if let nearestPerson = people.sorted(by: { $0.magnitude > $1.magnitude }).first {
            anchor.transform.translation = nearestPerson
        }

        try? await Task.sleep(for: .seconds(0.5))
    }
}

fileprivate func log(_ message: String) {
    print("[FollowPerson] \(message)")
}
