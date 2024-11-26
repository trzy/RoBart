//
//  WebRTCVAD.h
//  WebRTCVAD
//
//  Created by Bart Trzynadlowski on 4/19/23.
//
//  Note that the framework and this header must be named WebRTCVAD rather than WebRTC_VAD because
//  of a conflict with webrtc/common_audio/vad/include/webrtc_vad.h.
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

#import <Foundation/Foundation.h>

//! Project version number for WebRTC_VAD.
FOUNDATION_EXPORT double WebRTC_VADVersionNumber;

//! Project version string for WebRTC_VAD.
FOUNDATION_EXPORT const unsigned char WebRTC_VADVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <WebRTC_VAD/PublicHeader.h>

#import <WebRTCVAD/webrtc_vad.h>

