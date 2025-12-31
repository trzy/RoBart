//
//  Settings.swift
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

import Combine
import Foundation

class Settings: ObservableObject {
    static let shared = Settings()

    @Published var webRtcServerHostname: String = "" {
        didSet {
            UserDefaults.standard.set(webRtcServerHostname, forKey: Self.k_webRtcServerHostname)
            log("Set: \(Self.k_webRtcServerHostname) = \(webRtcServerHostname)")
        }
    }

    @Published var webRtcServerPort: String = "" {
        didSet {
            UserDefaults.standard.set(webRtcServerPort, forKey: Self.k_webRtcServerPort)
            log("Set: \(Self.k_webRtcServerPort) = \(webRtcServerPort)")
        }
    }

    var webRtcServerPortNumber: UInt16? {
        return UInt16(webRtcServerPort)
    }

    @Published var webRtcServerUseSsl: Bool = false {
        didSet {
            UserDefaults.standard.set(webRtcServerUseSsl, forKey: Self.k_webRtcServerUseSsl)
            log("Set: \(Self.k_webRtcServerUseSsl) = \(webRtcServerUseSsl)")
        }
    }

    private static let k_webRtcServerHostname = "webrtc_server_hostname"
    private static let k_webRtcServerPort = "webrtc_server_port"
    private static let k_webRtcServerUseSsl = "webrtc_server_use_ssl"

    fileprivate init() {
        if let value = UserDefaults.standard.string(forKey: Self.k_webRtcServerHostname) {
            self.webRtcServerHostname = value
        }

        if let value = UserDefaults.standard.string(forKey: Self.k_webRtcServerPort) {
            self.webRtcServerPort = value
        }

        self.webRtcServerUseSsl = UserDefaults.standard.bool(forKey: Self.k_webRtcServerUseSsl)
    }
}

fileprivate func log(_ message: String) {
    print("[Settings] \(message)")
}
