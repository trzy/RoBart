//
//  CollaborativeMappingStateView.swift
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

import SwiftUI

struct CollaborativeMappingStateView: View {
    @ObservedObject private var _peerManager = PeerManager.shared
    @ObservedObject private var _arSessionManager = ARSessionManager.shared

    var body: some View {
        HStack {
            let connected = _peerManager.peers.count > 0

            Image(systemName: connected ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                .imageScale(.large)
                .foregroundColor(connected ? .primary : .secondary)

            // Print (synchronized peers) / (connected peers)
            Text("\(_arSessionManager.participantCount)/\(_peerManager.remotePeerCount)")
                .foregroundColor(_arSessionManager.participantCount > 0 ? .primary : .secondary)
        }
    }
}

#Preview {
    CollaborativeMappingStateView()
}
