#
# __main__.py
# Bart Trzynadlowski
#
# Debug server main module. Listens for TCP connections from iPhone and takes keyboard commands from
# the user.
#

import asyncio
from dataclasses import dataclass
import platform
import sys
from typing import Any, Dict, List, Tuple, Type

from pydantic import BaseModel

from .networking import Server, Session, handler, MessageHandler


####################################################################################################
# Messages
#
# Keep these in sync with the corresponding messages in the iOS app.
####################################################################################################

class HelloMessage(BaseModel):
   message: str

class LogMessage(BaseModel):
    text: str

class DriveForDurationMessage(BaseModel):
    reverse: bool
    seconds: float
    speed: float

class DriveForDistanceMessage(BaseModel):
    reverse: bool
    meters: float
    speed: float


####################################################################################################
# Server
#
# Listens for connections and responds to messages from the iPhone app.
####################################################################################################

class RoBartDebugServer(MessageHandler):
    def __init__(self, port: int):
        super().__init__()
        self.sessions = set()
        self._server = Server(port=port, message_handler=self)
    
    async def run(self):
        await self._server.run()
    
    async def on_connect(self, session: Session):
        print("Connection from: %s" % session.remote_endpoint)
        await session.send(HelloMessage(message = "Hello from RoBart Python server running on %s %s" % (platform.system(), platform.release())))
        self.sessions.add(session)
    
    async def on_disconnect(self, session: Session):
        print("Disconnected from: %s" % session.remote_endpoint)
        self.sessions.remove(session)
    
    @handler(HelloMessage)
    async def handle_HelloMessage(self, session: Session, msg: HelloMessage, timestamp: float):
        print("Hello received: %s" % msg.message)

    @handler(LogMessage)
    async def handle_LogMessage(self, session: Session, msg: LogMessage, timestamp: float):
        print(f"\niPhone: {msg.text}")


####################################################################################################
# Command Console
#
# Interactive console that excepts keyboard input from the user and sends commands to iPhone.
####################################################################################################

class CommandConsole:
    @dataclass
    class Param:
        name: str                       # parameter name
        type: Type = None               # type of the parameter (int, float, str only)
        values: List[str] = None        # if not None, a list of allowed values
        range: Tuple[Any, Any] = None   # if type == int or float, range of acceptable values
        default: Any = None             # if not None, this is an optional param with a default value
    
    _commands: Dict[str, List[Param]] = {
        "q": [],
        "quit": [],
        "exit": [],
        "h": [],
        "help": [],
        "drive": [
            Param(name="amount", type=float),
            Param(name="units", type=str, values=[ "s", "m", "cm" ]),
            Param(name="direction", type=str, values=[ "f", "forward", "b", "backward" ], default="f"),
            Param(name="speed", type=float, range=(0, 0.05), default=0.03)
        ],
    }

    def __init__(self, tasks: List[asyncio.Task], server: RoBartDebugServer):
        self._tasks = tasks
        self._server = server

        # Validate params have been defined correctly
        for command, params in self._commands.items():
            # Optional params may not appear before non-optional ones
            optional_encountered = False
            names = set()
            for param in params:
                if optional_encountered and param.default is None:
                    raise ValueError(f"Command \"{command}\" is ill-defined: optional parameters must follow non-optional ones")
                optional_encountered = optional_encountered or (param.default is not None)
                if param.name in names:
                    raise ValueError(f"Command \"{command}\" has multiple parameters named \"{param.name}\"")
                names.add(param.name)
                if param.type not in [ str, int, float ]:
                    raise ValueError(f"Command \"{command}\" has invalid type for parameter \"{param.name}\". Must be one of: str, int, float")

    async def run(self):
        await asyncio.sleep(1)
        while True:
            # Read command and parse arguments
            words = await self._get_line_as_words()
            if len(words) == 0:
                continue
            command, arg_strings = words[0], words[1:]
            args = self._parse_args(command=command, args=arg_strings)
            if args is None:
                continue

            # Handle command
            if command == "q" or command == "quit" or command == "exit":
                self._cancel_tasks()
            elif command == "h" or command == "help":
                self._print_help()
            elif command == "drive":
                reverse = True if args["direction"][0] == "b" else False
                if args["units"] == "s":
                    await self.send(DriveForDurationMessage(reverse=reverse, seconds=args["amount"], speed=args["speed"]))
                else:
                    meters = args["amount"] * (0.01 if args["units"] == "cm" else 1.0)
                    await self.send(DriveForDistanceMessage(reverse=reverse, meters=meters, speed=args["speed"]))
                print("Sent drive command")
            else:
                print("Invalid command. Use \"help\" for a list of commands.")
    
    def _print_help(self):
        print("Commands:")
        print("---------")
        max_width = max([ len(command) for command in self._commands.keys() ])
        for command, params in self._commands.items():
            padding = max_width - len(command)
            print(f"{command}{' ' * padding}\t", end="")
            param_names = [ self._param_description(param=param) for param in params ]
            print(" ".join(param_names))
    
    @staticmethod
    def _param_description(param: Param) -> str:
        return "".join([
            "<" if param.default is None else "[",
            param.name,
            ":",
            param.type.__name__,
            ("=" + "|".join(param.values)) if param.values is not None else "",
            ">" if param.default is None else  "]"
        ])

    async def _get_line_as_words(self, prompt: str = ">>") -> List[str]:
        def print_prompt():
            sys.stdout.write(prompt)
            sys.stdout.flush()
        await asyncio.to_thread(print_prompt)
        line = (await asyncio.to_thread(sys.stdin.readline)).rstrip('\n').strip()
        return line.split()
    
    def _parse_args(self, command: str, args: List[str]) -> Dict[str, Any] | None:
        parsed_args: Dict[str, Any] = {}
        params = self._commands.get(command)
        if params is None:
            print(f"Error: Invalid command: {command}")
            return False
        for i, param in enumerate(params):
            out_of_bounds = i >= len(args)
            is_required = param.default is None
            if out_of_bounds:
                if is_required:
                    print(f"Error: Missing required parameter: {param.name}")
                    return None
                else:
                    parsed_args[param.name] = param.default
            else:
                value = self._try_parse_value(arg=args[i], param=param)
                if value is None:
                    return None
                parsed_args[param.name] = value
        return parsed_args
    
    @staticmethod
    def _try_parse_value(arg: str, param: Param) -> Any | None:
        if param.values is not None and len(param.values) > 0:
            # Arg must be one of the specified values
            if arg not in param.values:
                print(f"Error: Parameter \"{param.name}\" must be one of: {', '.join(param.values)}")
                return None
        if param.type == int or param.type == float:
            value = 0
            try:
                value = int(arg) if param.type == int else float(arg)
            except ValueError:
                required_type = "an integer" if param.type == int else "a float"
                print(f"Error: Parameter \"{param.name}\" must be {required_type} value")
                return None
            if param.range is not None:
                if value < min(param.range) or value > max(param.range):
                    print(f"Error: Parameter \"{param.name}\" must be in range: [{min(param.range)},{max(param.range)}]")
                    return None
            return value
        else:
            # Assume str
            return arg

    async def send(self, message: BaseModel):
        for session in self._server.sessions:
            await session.send(message)

    def _cancel_tasks(self):
        print("Canceling tasks...")
        for task in self._tasks:
            task.cancel()


####################################################################################################
# Program Entry Point
####################################################################################################

if __name__ == "__main__":
    tasks = []
    server = RoBartDebugServer(port=8000)
    console = CommandConsole(tasks=tasks, server=server)
    loop = asyncio.new_event_loop()
    tasks.append(loop.create_task(server.run()))
    tasks.append(loop.create_task(console.run()))
    try:
        loop.run_until_complete(asyncio.gather(*tasks))
    except asyncio.exceptions.CancelledError:
        print("\nExited normally")
    except:
        print("\nExited due to uncaught exception")
    