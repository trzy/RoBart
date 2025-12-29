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

# We store only up to two clients who have signaled readiness and been assigned a role.
# TODO: need to support arbitrary number of clients and match two at a time according to a "room ID"
client_initiator: WebSocket | None = None
client_responder: WebSocket | None = None

async def handle_role_assignment(client: WebSocket, data: str) -> bool:
    global client_initiator
    global client_responder
    
    try:
        msg = json.loads(data)
        if msg["type"] == "ReadyToConnectMessage":
            # First, decide assignment
            if client_initiator is None:
                client_initiator = client
            elif client_responder is None:
                client_responder = client
            
            # Next, when we have both peers with assigned roles, send role assignment message to
            # kick off connection process between them
            if client_initiator is not None and client_responder is not None:
                print("SENDING ROLE ASSIGNMENT...")
                await client_initiator.send_text(json.dumps({
                    "type": "RoleMessage",
                    "role": "initiator"
                }))
                await client_responder.send_text(json.dumps({
                    "type": "RoleMessage",
                    "role": "responder"
                }))
                return True
            
    except Exception as e:
        print(f"Error: Ignoring non-JSON message: {e}")

    return False


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    global client_initiator
    global client_responder

    endpoint = f"{websocket.client.host}:{websocket.client.port}"
    await websocket.accept()
    
    try:
        while True:
            # Receive message from this client
            data = await websocket.receive_text()
            print(f"Received from {endpoint}: {data[:100]}...")
            
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
        print(f"Client disconnected: {endpoint}")
        if client_initiator == websocket:
            client_initiator = None
        if client_responder == websocket:
            client_responder = None

# Must be added after WebSocket route
app.mount("/", StaticFiles(directory="server/static", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)