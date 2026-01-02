# RoBart: iPhone-based Robot with WebRTC Remote Teleoperation
*Copyright 2024-2025 Bart Trzynadlowski*

This is the `webrtc-teleop` branch of RoBart. Please [see here](https://github.com/trzy/RoBart) for the main branch containing VLM-controlled RoBart. This branch contains a simple implementation of WebRTC-based teleoperation for RoBart. All of the VLM and AR features have been removed.

## Usage

### Basic Usage

To use it, start the simple Python signaling server (after installing `requirements.txt`):

```
python -m server
```

Then, open [http://localhost:8000](http://localhost:8000) for the teleop interface. The WASD keys on the keyboard control the robot. 

Finally, launch the iOS app, which will automatically try to connect via the signaling server. Ensure the IP address used by the iOS app matches where the server is running. It may take a while for the WebRTC stream to stabilize, even on a home LAN, but after 30 seconds to a minute, it should be perfectly usable.

### TURN Servers

ICE servers are provided to clients by the signaling server. STUN servers are hard-coded to public Google servers for now but TURN servers can be
supplied using `--turn-servers`, which takes a comma-delimited list of server addresses along with the protocol prefix (`turn:` or `turns:`, depending on whether TLS is required) and port number. Optionally, credentials may be provided with `--turn-users` and `--turn-passwords`. 

```
python -m server --turn-servers=turn:192.168.0.101:3478,turns:myturnserver.domain.com:5349 --turn-users=user1,user2 --turn-passwords=pass1,pass2
```

To force the clients to use a TURN relay (ICE transport policy of `relay` rather than `all`), `--relay` can be used. The server sends `ServerConfigurationMessage` to clients in order to establish their role (initiator or responder), the ICE servers, whether to use relay mode, and to signal that the connection process may begin.

## Future Work

- The connection flow can surely be made more robust. There are probably edge cases where a client (particularly the iOS one) can get stuck
  indefinitely. I am fairly confident these are fixable and that `AsyncWebRtcClient`'s state machine approach is sufficiently flexible.
- The signal server can easily be improved to support more than a single client pair at a time using some sort of session or "room" ID to match  
  them.
- Reintroduce AR and spatial mapping. This will require learning how to construct the video stream at a lower level and manually inputting frames.