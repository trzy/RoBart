import argparse
import json
import os

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

app = FastAPI()

# Enable CORS for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

force_relay = False
turn_servers = []
turn_users = []
turn_passwords = []

def createServerConfigMessage(role: str) -> str:
    return json.dumps({
        "type": "ServerConfigurationMessage",
        "role": role,
        "turnServers": turn_servers,
        "turnUsers": turn_users,
        "turnPasswords": turn_passwords,
        "relayOnly": force_relay,
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
    parser = argparse.ArgumentParser("server")
    parser.add_argument("--port", metavar="number", action="store", type=int, default=8000, help="Port to listen on")
    parser.add_argument("--relay", action="store_true", help="Force clients to use a TURN relay, avoiding peer-to-peer connections")
    parser.add_argument("--turn-servers", metavar="addresses", action="store", type=str, default="192.168.0.101:3478,71.92.165.74:3478", help="Comma-delimited list of host:port")
    parser.add_argument("--turn-users", metavar="usernames", action="store", type=str, default="bart", help="Comma-delimited list of usernames. If single username, applies to all servers.")
    parser.add_argument("--turn-passwords", metavar="passwords", action="store", type=str, default="bart", help="Comma-delimited list of passwords. Must match number of usernames.")
    parser.add_argument("--cert-dir", metavar="path", action="store", type=str, help="Directory containing SSL certificate files (privkey.pem and fullchain.pem)")
    options = parser.parse_args()

    ssl_keyfile: str | None = None
    ssl_certfile: str | None = None
    if options.cert_dir:
        ssl_keyfile = os.path.join(options.cert_dir, "privkey.pem")
        ssl_certfile = os.path.join(options.cert_dir, "fullchain.pem")
        files_found = True
        if not os.path.exists(ssl_keyfile):
            print(f"Error: privkey.pem does not exist. Make sure it is located at '{ssl_keyfile}'.")
            files_found = False
        if not os.path.exists(ssl_certfile):
            print(f"Error: fullchain.pem does not exist. Make sure it is located at '{ssl_certfile}'.")
            files_found = False
        if not files_found:
            exit(1)
        print(f"SSL support enabled. Using certificates in '{options.cert_dir}'.")
    else:
        print("SSL support disabled.")

    turn_servers = options.turn_servers.strip().split(",")
    turn_users = options.turn_users.strip().split(",")
    turn_passwords = options.turn_passwords.strip().split(",")

    if len(turn_users) != len(turn_passwords):
        parser.error("Number of TURN usernames (--turn-users) and passwords (--turn-passwords) must match")
    if len(turn_users) == 1:
        turn_users = [ turn_users[0] ] * len(turn_servers)
    if len(turn_passwords) == 1:
        turn_passwords = [ turn_passwords[0] ] * len(turn_servers)
    if len(turn_users) != len(turn_servers):
        parser.error("Number of TURN usernames (--turn-users) and passwords (--turn-passwords) must match the number of TURN servers or both be one")

    if len(turn_servers) > 0:
        print("TURN servers:")
        for i in range(len(turn_servers)):
            print(f"  {turn_servers[i]}, user={turn_users[i]}")
    else:
        print("No TURN servers")

    force_relay = options.relay
    if force_relay:
        print("Clients will be directed to use TURN relay")

    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, ssl_keyfile=ssl_keyfile, ssl_certfile=ssl_certfile)