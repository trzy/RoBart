# RoBart: iPhone-based Robot with WebRTC Remote Teleoperation
*Copyright 2024-2025 Bart Trzynadlowski*

This is the `webrtc-teleop` branch of RoBart. Please [see here](https://github.com/trzy/RoBart) for the main branch containing VLM-controlled RoBart. This branch contains a simple implementation of WebRTC-based teleoperation for RoBart. All of the VLM and AR features have been removed.
To use it, start the simple Python signaling server (after installing `requirements.txt`):

```
python -m server
```

Then, open [http://localhost:8000](http://localhost:8000) for the teleop interface. The WASD keys on the keyboard control the robot. 

Finally, launch the iOS app, which will automatically try to connect via the signaling server. Ensure the IP address used by the iOS app matches where the server is running. It may take a while for the WebRTC stream to stabilize, even on a home LAN, but after 30 seconds to a minute, it should be perfectly usable.

### TODO

- Improve signaling server and overall signaling flow (sometimes re-connects fail). The iOS side may need to explicitly disconnect from the 
  signaling server when retrying and we should implement the concept of session or "room" IDs to match clients. 
- Detection of connection failures in iOS is brittle and the culprit is likely to be the task that monitors connection state after SDP exchange.
- Try to simplify the `AsyncWebRtcClient`, which feels a bit brittle. I think making it an actor and using async is not worth the trouble here. 