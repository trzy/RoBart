//
//  CollaborativeMappingStateView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//

import SwiftUI

struct CollaborativeMappingStateView: View {
    @ObservedObject private var _peerManager = PeerManager.shared
    @ObservedObject private var _arSessionManager = ARSessionManager.shared

    var body: some View {
        HStack {
            let connected = _peerManager.peers.count > 0
            let numRemotePeers = max(0, _peerManager.peers.count - 1)
            Image(systemName: connected ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                .imageScale(.large)
                .foregroundColor(connected ? .primary : .secondary)
            Text("\(_arSessionManager.participantCount)/\(numRemotePeers)")
                .foregroundColor(_arSessionManager.participantCount > 0 ? .primary : .secondary)
        }
    }
}

#Preview {
    CollaborativeMappingStateView()
}
