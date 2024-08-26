//
//  PeerManager.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//

import MultipeerConnectivity

class PeerManager: NSObject, ObservableObject {
    static let shared = PeerManager()

    @Published var peers: [MCPeerID] = []
    @Published private(set) var receivedMessage: (peerID: MCPeerID, data: Data)?

    private let _serviceType = "robart"
    private let _ourPeerId = MCPeerID(displayName: UIDevice.current.name)
    private let _serviceAdvertiser: MCNearbyServiceAdvertiser
    private let _serviceBrowser: MCNearbyServiceBrowser
    private let _session: MCSession
    private var _roleByPeerID: [MCPeerID: Role] = [:]

    fileprivate override init() {
        _session = MCSession(peer: _ourPeerId, securityIdentity: nil, encryptionPreference: .none)
        _serviceAdvertiser = MCNearbyServiceAdvertiser(peer: _ourPeerId, discoveryInfo: nil, serviceType: _serviceType)
        _serviceBrowser = MCNearbyServiceBrowser(peer: _ourPeerId, serviceType: _serviceType)

        super.init()

        _session.delegate = self
        _serviceAdvertiser.delegate = self
        _serviceBrowser.delegate = self

        _serviceAdvertiser.startAdvertisingPeer()
        _serviceBrowser.startBrowsingForPeers()
    }

    deinit {
        _serviceAdvertiser.stopAdvertisingPeer()
        _serviceBrowser.stopBrowsingForPeers()
    }

    func send(_ message: SimpleBinaryMessage, to peerIDs: [MCPeerID], reliable: Bool) {
        guard !peers.isEmpty else { return }
        do {
            try _session.send(message.serialize(), toPeers: peerIDs, with: reliable ? .reliable : .unreliable)
        } catch {
            log("Failed to send: \(error.localizedDescription)")
        }
    }

    func send(_ message: SimpleBinaryMessage, withRole role: Role, reliable: Bool) {
        let peerIDs = peers.filter { (peerID: MCPeerID) in
            if let peerRole = _roleByPeerID[peerID],
               role == peerRole {
                return true
            }
            return false
        }
        send(message, to: peerIDs, reliable: reliable)
    }

    func sendToAll(_ message: SimpleBinaryMessage, reliable: Bool) {
        send(message, to: peers, reliable: reliable)
    }
}

extension PeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept invitation from peer
        invitationHandler(true, _session)
        log("Accepted invitation from \(peerID)")
    }
}

extension PeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Invite peers we've discovered
        browser.invitePeer(peerID, to: _session, withContext: nil, timeout: 10)
        log("Invited \(peerID)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    }
}

extension PeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            log("Connected peers: \(session.connectedPeers)")
            peers = session.connectedPeers

            // Remove disconnected peers from role map
            let oldPeerIDs = Set<MCPeerID>(_roleByPeerID.keys)
            let disconnectedPeerIDs = oldPeerIDs.subtracting(peers)
            for peerID in disconnectedPeerIDs {
                _roleByPeerID.removeValue(forKey: peerID)
            }

            // Broadcast our role to all connected peers
            sendToAll(PeerRoleMessage(role: Settings.shared.role), reliable: true)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let msg = PeerRoleMessage.deserialize(from: data) {
                _roleByPeerID[peerID] = msg.role
                return
            }

            receivedMessage = (peerID: peerID, data: data)
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
    }

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
    }
}

fileprivate func log(_ message: String) {
    print("[PeerManager] \(message)")
}
