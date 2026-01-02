//
//  RemoteVideoView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 12/28/25.
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
import UIKit
import WebRTC

struct RemoteVideoView: UIViewRepresentable {
    private let _size: CGSize
    private weak var _client: NewWebRtcClient?
    private var _view: RTCMTLVideoView?

    init(size: CGSize, client: NewWebRtcClient) {
        _size = size
        _client = client
    }

    // Create a Coordinator to hold the client reference for cleanup
    func makeCoordinator() -> Coordinator {
        Coordinator(client: _client)
    }

    func makeUIView(context: Context) -> UIView {
        let frame = CGRect(origin: CGPoint(x: 0, y: 0), size: _size)
        let view = RTCMTLVideoView(frame: frame)
        view.videoContentMode = .scaleAspectFill
        Task { await _client?.addRemoteVideoView(view) }
        return view
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        Task { await coordinator.client?.removeRemoteVideoView(uiView) }
    }

    func updateUIView(_ uiView: UIView, context: Context) {
    }

    class Coordinator {
        weak var client: NewWebRtcClient?
        init(client: NewWebRtcClient?) {
            self.client = client
        }
    }
}
