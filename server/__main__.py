from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles 

import json

app = FastAPI()

# Enable CORS for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def createServerConfigMessage(role: str) -> str:
    return json.dumps({
        "type": "RoleMessage",
        "role": role,
        "turnServer": "192.168.0.128:3478", #"71.92.165.74:3478",
        "turnUser": "bart",
        "turnPassword": "bart"
    })

# We store only up to two clients who have signaled readiness and been assigned a role.
# TODO: need to support arbitrary number of clients and match two at a time according to a "room ID"
client_initiator: WebSocket | None = None
client_responder: WebSocket | None = None

def endpoint(websocket: WebSocket) -> str:
    return f"{websocket.client.host}:{websocket.client.port}"

def client_info() -> str:
    initiator = f"{endpoint(client_initiator)}" if client_initiator else "none"
    responder = f"{endpoint(client_responder)}" if client_responder else "none"
    return f"clients {{initiator={initiator}, responder={responder}}}"

def log(message: str):
    print(f"{client_info()} -- {message}")

async def handle_role_assignment(client: WebSocket, data: str) -> bool:
    global client_initiator
    global client_responder
    
    try:
        msg = json.loads(data)
        if msg["type"] == "ReadyToConnectMessage":
            # First, decide assignment. Since we assign based on the ReadyToConnect message, we must
            # be careful not to assign a client to two roles if it sends the message twice before
            # another connects.
            if client not in [ client_initiator, client_responder ]:
                if client_initiator is None:
                    client_initiator = client
                elif client_responder is None:
                    client_responder = client

            log("Role assignment")
            
            # Next, when we have both peers with assigned roles, send role assignment message to
            # kick off connection process between them
            if client_initiator is not None and client_responder is not None:
                log("Sending role assignment...")
                await client_initiator.send_text(createServerConfigMessage(role="initiator"))
                await client_responder.send_text(createServerConfigMessage(role="responder"))
                return True
            
    except Exception as e:
        log(f"Error: Ignoring non-JSON message: {e}")

    return False

def log_message(websocket: WebSocket, data: str):
    try:
        # Log everything except ICE candidate messages, which are too numerous
        msg = json.loads(data)
        if msg["type"] != "ICECandidateMessage":
            log(f"Received from {endpoint(websocket)}: {data[0:100]}")
    except Exception as e:
        log(f"Received non-JSON message from {endpoint(websocket)}: {data}")

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    global client_initiator
    global client_responder

    await websocket.accept()
    log(f"New connection from {endpoint(websocket)}")
    
    try:
        while True:
            # Receive message from this client
            data = await websocket.receive_text()
            log_message(websocket, data)
            
            # Handle role assignment
            if await handle_role_assignment(client=websocket, data=data):
                continue

            # All other messages: broadcast to all other clients
            for client in [ client_initiator, client_responder ]:
                if client and client != websocket:
                    try:
                        await client.send_text(data)
                    except:
                        pass
                        
    except WebSocketDisconnect:
        if client_initiator == websocket:
            client_initiator = None
        if client_responder == websocket:
            client_responder = None
        log(f"Client disconnected: {endpoint(websocket)}")

# Must be added after WebSocket route
app.mount("/", StaticFiles(directory="server/static", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)