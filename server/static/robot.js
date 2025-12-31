/*
 * RoBart control
 */

let pc = null;
let dataChannel = null;
let ws = null;
let myRole = null;
let iceCandidateQueue = [];
let localStream = null;

// ICE servers for NAT traversal
const stunServers = [
    "stun:stun.l.google.com:19302",
    "stun:stun.l.google.com:5349",
    "stun:stun1.l.google.com:3478",
    "stun:stun1.l.google.com:5349",
    "stun:stun2.l.google.com:19302",
    "stun:stun2.l.google.com:5349",
    "stun:stun3.l.google.com:3478",
    "stun:stun3.l.google.com:5349",
    "stun:stun4.l.google.com:19302",
    "stun:stun4.l.google.com:5349",
];

let config = null;

// UI Elements
const websocketEndpoint = document.getElementById('websocketEndpoint');
const connectBtn = document.getElementById('connectBtn');
const transmitVideoBtn = document.getElementById('transmitVideoBtn');
//const sendBtn = document.getElementById('sendBtn');
//const messageInput = document.getElementById('messageInput');
//const messagesDiv = document.getElementById('messages');
const statusDiv = document.getElementById('status');

function enqueueICECandidate(candidate) {
    iceCandidateQueue.push(candidate);
}

async function processEnqueuedICECandidates() {
    for (const candidate of iceCandidateQueue) {
        await pc.addIceCandidate(candidate);
    }
    iceCandidateQueue = [];
}

function createReadyToConnectMessage() {
    const message = { type: "ReadyToConnectMessage" }
    return JSON.stringify(message)
}

function createOfferMessageFromLocalDescription() {
    const offer = JSON.stringify(pc.localDescription);
    const message = { type: "OfferMessage", data: offer };
    return JSON.stringify(message);
}

function createAnswerMessageFromLocalDescription() {
    const offer = JSON.stringify(pc.localDescription);
    const message = { type: "AnswerMessage", data: offer };
    return JSON.stringify(message);
}

function createICECandidateMessage(candidate) {
    console.log("ICE JSON: " + JSON.stringify(candidate));
    const message = { type: "ICECandidateMessage", data: JSON.stringify(candidate) };
    return JSON.stringify(message);
}

function createConnectionConfiguration(serverConfigMessage) {
    let config = {
        iceServers: [
            { urls: stunServers }
        ],
        iceTransportPolicy: serverConfigMessage.relayOnly ? "relay" : "all"
    };

    console.log(`ICE transport policy: ${config.iceTransportPolicy}`);

    // Add TURN servers if provided
    const numServers = serverConfigMessage.turnServers.length;
    const numUsers = serverConfigMessage.turnUsers.length;
    const numPasswords = serverConfigMessage.turnPasswords.length;
    if (numServers != numUsers  ||
        numUsers != numPasswords) {
        console.error(`Number of TURN servers (${numServers}), usernames (${numUsers}), and passwords (${numPasswords}) do not match! Ignoring.`);
    } else {
        for (let i = 0; i < numServers; i++) {
            let server = { urls: "turn:" + serverConfigMessage.turnServers[i] };
            if (serverConfigMessage.turnUsers[i]) {
                server.username = serverConfigMessage.turnUsers[i];
            }
            if (serverConfigMessage.turnPasswords[i]) {
                server.credential = serverConfigMessage.turnPasswords[i];
            }
            config.iceServers.push(server);
        }
    }

    return config;
}

function stop() {
    if (pc) {
        pc.close();
    }
    dataChannel = null;
    iceCandidateQueue = [];
}

function autoDetectWebSocketEndpoint() {
    const protocol = window.location.protocol == "https:" ? "wss:" : "ws:";
    const hostname = window.location.hostname;
    const port = window.location.port;
    websocketEndpoint.value = `${protocol}//${hostname}:${port}/ws`;
}

autoDetectWebSocketEndpoint();

// Connect to signaling server
connectBtn.onclick = () => {
    ws = new WebSocket(websocketEndpoint.value);

    ws.onopen = () => {
        updateStatus('Connected to signaling server, waiting for role assignment...');
        connectBtn.disabled = true;

        // Indicate to server that we are ready to begin
        ws.send(createReadyToConnectMessage());
    };

    ws.onmessage = async (event) => {
        const message = JSON.parse(event.data);
        console.log('Signaling message:', message.type);

        if (message.type === 'ServerConfigurationMessage') {
            // Server assigned us a role
            myRole = message.role;
            updateStatus(`Role: ${myRole}`);

            // Create connection configuration
            config = createConnectionConfiguration(message)

            if (myRole === 'initiator') {
                // We're the first peer, wait for responder
                updateStatus('Waiting for peer to connect...');
            } else {
                // We're the responder, wait for offer
                updateStatus('Connected as responder, waiting for offer...');
            }

            if (myRole === 'initiator') {
                updateStatus('Peer connected, creating offer...');
                initPeerConnection();
                createOffer();
            }

        } else if (message.type === 'OfferMessage') {
            // Responder receives offer
            if (!pc) {
                if (!config) {
                    console.error("ServerConfigurationMessage was not received before offer!");
                }
                initPeerConnection();
            }
            const offer = JSON.parse(message.data);
            await pc.setRemoteDescription(offer);
            await processEnqueuedICECandidates();

            const answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            ws.send(createAnswerMessageFromLocalDescription());
            updateStatus('Sent answer, establishing connection...');

        } else if (message.type === 'AnswerMessage') {
            // Initiator receives answer
            const answer = JSON.parse(message.data);
            await pc.setRemoteDescription(answer);
            await processEnqueuedICECandidates();
            updateStatus('Received answer, establishing connection...');

        } else if (message.type === 'ICECandidateMessage' && message.data) {
            const candidate = JSON.parse(message.data);
            try {
                if (pc && pc.remoteDescription) {
                    await pc.addIceCandidate(candidate);
                } else {
                    enqueueICECandidate(candidate);
                }
            } catch (err) {
                console.error('Error adding ICE candidate:', err);
            }
        } else if (message.type == 'HelloMessage') {
            console.log('Peer said hello:', message.message);
        }
    };

    ws.onerror = (err) => {
        updateStatus('WebSocket error - is server running?');
        console.error('WebSocket error:', err);
    };

    ws.onclose = () => {
        updateStatus('Disconnected from signaling server');
        connectBtn.disabled = false;
    };
};

// Initialize peer connection
function initPeerConnection() {
    if (pc) {
        console.log("Closing old peer connection");
        stop();
    }
    pc = new RTCPeerConnection(config);

    pc.addStream(localStream);

    // ICE candidate handling
    pc.onicecandidate = (e) => {
        if (e.candidate) {
            console.log('ICE candidate generated: ' + e.candidate);
            ws.send(createICECandidateMessage(e.candidate));
        }
    };

    // Connection state
    pc.onconnectionstatechange = () => {
        updateStatus('Connection: ' + pc.connectionState);
        if (pc.connectionState === 'connected') {
            updateStatus('WebRTC Connected! You can now chat.');
        } else if (pc.connectionState == 'failed') {
            updateStatus("Connection FAILED");
            stop();
        }
    };

    // Data channel from remote peer
    pc.ondatachannel = (e) => {
        dataChannel = e.channel;
        setupDataChannel();
    };

    // Stream from remote peer
    pc.onaddstream = (e) => {
        console.log(`Got remote stream`);
        const remoteVideo = document.getElementById('remoteVideo');
        remoteVideo.srcObject = e.stream;
    };

    // If we're initiator, create data channel
    if (myRole === 'initiator') {
        dataChannel = pc.createDataChannel('chat');
        setupDataChannel();
    }
}

// Setup data channel handlers
function setupDataChannel() {
    dataChannel.onopen = () => {
        updateStatus('Data channel open! You can now chat.');
        //sendBtn.disabled = false;
    };

    dataChannel.onclose = () => {
        updateStatus('Data channel closed');
        //sendBtn.disabled = true;
    };

    dataChannel.onmessage = (e) => {
        addMessage('Peer: ' + e.data, 'received');
    };
}

// Create offer (initiator only)
async function createOffer() {
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    ws.send(createOfferMessageFromLocalDescription());
    console.log('Offer:', JSON.stringify(pc.localDescription));
    updateStatus('Sent offer, waiting for answer...');
}

// // Send message
// sendBtn.onclick = () => {
//     const msg = messageInput.value.trim();
//     if (msg && dataChannel && dataChannel.readyState === 'open') {
//         dataChannel.send(msg);
//         addMessage('You: ' + msg, 'sent');
//         messageInput.value = '';
//     }
// };

// Send on Enter key
// messageInput.onkeypress = (e) => {
//     if (e.key === 'Enter') {
//         sendBtn.onclick();
//     }
// };

// UI helpers
function addMessage(text, className) {
    const div = document.createElement('div');
    div.className = 'msg ' + className;
    div.textContent = text;
    messagesDiv.appendChild(div);
    messagesDiv.scrollTop = messagesDiv.scrollHeight;
}

function updateStatus(text) {
    statusDiv.textContent = 'Status: ' + text;
}

// Disable send initially
// sendBtn.disabled = true;


/***************************************************************************************************
 Robot Control
***************************************************************************************************/

const MotionDirection = Object.freeze({
    FORWARD: 'FORWARD',
    BACKWARD: 'BACKWARD',
    LEFT: 'LEFT',
    RIGHT: 'RIGHT',
    STOP: 'STOP',
});

const commandByMotionDirection = {
    'FORWARD': 'f',
    'BACKWARD': 'b',
    'LEFT': 'l',
    'RIGHT': 'r',
    'STOP': 's'
};

let inputDirection = MotionDirection.STOP;

// DPad UI buttons
const dpadUp = document.querySelector('.dpad-btn[data-direction="up"]');
const dpadDown = document.querySelector('.dpad-btn[data-direction="down"]');
const dpadLeft = document.querySelector('.dpad-btn[data-direction="left"]');
const dpadRight = document.querySelector('.dpad-btn[data-direction="right"]');

function updateButtons() {
    const buttons = [ dpadUp, dpadDown, dpadLeft, dpadRight ];
    for (let button of buttons) {
        button.classList.remove("active");
    }

    switch (inputDirection) {
    case MotionDirection.FORWARD:   dpadUp.classList.add("active"); break;
    case MotionDirection.BACKWARD:  dpadDown.classList.add("active"); break;
    case MotionDirection.LEFT:      dpadLeft.classList.add("active"); break;
    case MotionDirection.RIGHT:     dpadRight.classList.add("active"); break;
    default:    break;
    }
}

document.addEventListener('keydown', (event) => {
    console.log('Key pressed:', event.key);
    switch (event.key) {
        case 'w':
            inputDirection = MotionDirection.FORWARD;
            break;
        case 's':
            inputDirection = MotionDirection.BACKWARD;
            break;
        case 'a':
            inputDirection = MotionDirection.LEFT;
            break;
        case 'd':
            inputDirection = MotionDirection.RIGHT;
            break;
    }
    updateButtons();
});

document.addEventListener('keyup', (event) => {
    switch (event.key) {
        case 'w':
            if (inputDirection == MotionDirection.FORWARD) {
                inputDirection = MotionDirection.STOP;
            }
            break;
        case 's':
            if (inputDirection == MotionDirection.BACKWARD) {
                inputDirection = MotionDirection.STOP;
            }
            break;
        case 'a':
            if (inputDirection == MotionDirection.LEFT) {
                inputDirection = MotionDirection.STOP;
            }
            break;
        case 'd':
            if (inputDirection == MotionDirection.RIGHT) {
                inputDirection = MotionDirection.STOP;
            }
            break;
    }
    updateButtons();
});

const throttleSlider = document.getElementById('throttleSlider');
const throttleLabel = document.getElementById('throttleLabel');

function getThrottleValue() {
    return parseFloat(throttleSlider.value);
}

function setThrottleValue(value) {
    throttleSlider.value = value;
    throttleLabel.textContent = `Throttle: ${value.toFixed(2)}`;
}

// Update throttle label
throttleSlider.addEventListener('input', (e) => {
    const value = parseFloat(e.target.value).toFixed(2);
    throttleLabel.textContent = `Throttle: ${value}`;
});

throttleSlider.addEventListener('change', (e) => {
    const throttle = parseFloat(e.target.value);
    console.log('Throttle changed to:', throttle);
});

window.addEventListener("blur", (event) => {
    // Window lost focus
    inputDirection = MotionDirection.STOP;
});

window.addEventListener("focus", (event) => {
    // Window focus gained
});

const cameraSelectMenu = document.getElementById("cameraView");
cameraSelectMenu.addEventListener("change", function(event) {
    // 'event.target' refers to the <select> element itself
    const selectedValue = event.target.value;
    console.log("Camera selection changed:", selectedValue);
    if (dataChannel && dataChannel.readyState == 'open') {
        dataChannel.send(`c${selectedValue}`);
    }
});

let lastTime = 0;
const targetInterval = 1000 / 10;   // target interval for N Hz: 1000 ms / N frames = ms/frame

function animationLoop(timestamp) {
  const elapsed = timestamp - lastTime;
  if (elapsed >= targetInterval) {
    lastTime = timestamp - (elapsed % targetInterval);

    if (dataChannel && dataChannel.readyState === 'open') {
        // Send motion command on data channel followed by throttle value
        const directionCommand = commandByMotionDirection[inputDirection];
        const throttleCommand = `${getThrottleValue()}`;
        const command = directionCommand + throttleCommand;
        dataChannel.send(command);
        console.log(`Sent: ${command}`);
    }
  }
  requestAnimationFrame(animationLoop);
}

requestAnimationFrame(animationLoop);

/***************************************************************************************************
 Video and Audio
***************************************************************************************************/

function setVideoTransmissionEnabled(enable) {
    if (localStream) {
        if (localStream.getVideoTracks().length > 0) {
            const videoTrack = localStream.getVideoTracks()[0];
            videoTrack.enabled = enable;
            transmitVideoBtn.textContent = enable ? "Stop" : "Transmit";
        }

        if (localStream.getAudioTracks().length > 0) {
            const audioTrack = localStream.getAudioTracks()[0];
            audioTrack.enabled = enable;
            transmitVideoBtn.textContent = enable ? "Stop" : "Transmit";
        }
    }
}

function getVideoTransmissionEnabled() {
    if (localStream && localStream.getVideoTracks().length > 0) {
        const videoTrack = localStream.getVideoTracks()[0];
        return videoTrack.enabled;
    }
    return false;
}

transmitVideoBtn.onclick = () => {
    const newState = !getVideoTransmissionEnabled();
    setVideoTransmissionEnabled(newState);
}

async function initVideoStream() {
    const localVideo = document.getElementById('localVideo');

    const constraints = {
        video: true,
        audio: true
    };

    try {
        const stream = await navigator.mediaDevices.getUserMedia(constraints);
        localVideo.srcObject = stream;
        return stream;
    } catch (error) {
        console.log('Error: Failed to obtain video stream:', error);
    }

    return null;
}

localStream = await initVideoStream();
if (localStream && localStream.getVideoTracks().length > 0) {
    console.log(`Using video device: ${localStream.getVideoTracks()[0].label}`);
    setVideoTransmissionEnabled(false);
}