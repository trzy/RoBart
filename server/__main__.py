#
# __main__.py
# Bart Trzynadlowski
#
# Debug server main module. Listens for TCP connections from iPhone and takes keyboard commands from
# the user.
#

import asyncio
import base64
from dataclasses import dataclass
import os
import platform
import sys
from typing import Any, Awaitable, Callable, Dict, List, Tuple, Type

import numpy as np
from pydantic import BaseModel

from .image_viewer import ImageViewer
from .messages import *
from .navigation import NavigationUI
from .networking import Server, Session, handler, MessageHandler


####################################################################################################
# Server
#
# Listens for connections and responds to messages from the iPhone app.
####################################################################################################

class RoBartDebugServer(MessageHandler):
    def __init__(self, port: int, navigation_ui: NavigationUI, image_viewer: ImageViewer):
        super().__init__()
        self.sessions = set()
        self._server = Server(port=port, message_handler=self)
        self._navigation_ui = navigation_ui
        self._image_viewer = image_viewer

    async def run(self):
        await self._server.run()

    async def send_to_clients(self, message: BaseModel):
        for session in self._server.sessions:
            await session.send(message)

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

    @handler(HoverboardRTTMeasurementMessage)
    async def handle_HoverboardRTTMeasurementMessage(self, session: Session, msg: HoverboardRTTMeasurementMessage, timestamp: float):
        samples = np.array(msg.rttSeconds) * 1e3    # to ms
        mean = np.mean(samples)
        min = np.min(samples)
        max = np.max(samples)
        p99 = np.quantile(samples, 0.99)
        p95 = np.quantile(samples, 0.95)
        p90 = np.quantile(samples, 0.90)
        print("\niOS <-> Hoverboard RTT")
        print("----------------------")
        print(f"Mean = {mean:.1f} ms")
        print(f"Min  = {min:.1f} ms")
        print(f"90%  = {p90:.1f} ms")
        print(f"95%  = {p95:.1f} ms")
        print(f"99%  = {p99:.1f} ms")
        print(f"Max  = {max:.1f} ms")
        print("")

    @handler(AngularVelocityMeasurementMessage)
    async def handle_AngularVelocityMeasurementMessage(self, session: Session, msg: AngularVelocityMeasurementMessage, timestamp: float):
        print(f"Measured angular velocity = {msg.angularVelocityResult} deg/sec")
    
    @handler(OccupancyMapMessage)
    async def handle_OccupancyMapMessage(self, session: Session, msg: OccupancyMapMessage, timestamp: float):
        self._navigation_ui.show(occupancy_map=msg)
    
    @handler(AnnotatedViewMessage)
    async def handle_AnnotatedViewMessage(self, session: Session, msg: AnnotatedViewMessage, timestamp: float):
        self._image_viewer.show(image=base64.b64decode(msg.imageBase64), name="Robot Annotated View")
    
    @handler(AIStepMessage)
    async def handle_AIStepMessage(self, session: Session, msg: AIStepMessage, timestamp: float):
        dir = os.path.join("data", msg.timestamp, f"{msg.stepNumber}")
        os.makedirs(dir)
        with open(file=os.path.join(dir, "input.txt"), mode="w") as fp:
            fp.write(msg.modelInput)
        with open(file=os.path.join(dir, "output.txt"), mode="w") as fp:
            fp.write(msg.modelOutput)
        for (name, image_base64) in msg.imagesBase64.items():
            image_bytes = base64.b64decode(image_base64)
            with open(file=os.path.join(dir, f"{name}.jpg"), mode="wb") as fp:
                fp.write(image_bytes)
        print(f"Logged AI step to: {dir}")


####################################################################################################
# Command Console
#
# Interactive console that accepts keyboard input from the user and sends commands to iPhone.
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
        "?": [],
        "help": [],
        "drive": [
            Param(name="amount", type=float),
            Param(name="units", type=str, values=[ "s", "m", "cm" ]),
            Param(name="direction", type=str, values=[ "f", "forward", "b", "backward" ], default="f"),
            Param(name="speed", type=float, range=(0, 0.05), default=0.03)
        ],
        "s": [],
        "stop": [],
        "rot": [
            Param(name="degrees", type=float, range=(-360,360))
        ],
        "df": [
            Param(name="delta_meters", type=float)
        ],
        "watchdog": [
            Param(name="timeout_sec", type=float)
        ],
        "pwm": [
            Param(name="hz", type=int, range=(50,50000))
        ],
        "throttle": [
            Param(name="max", type=float, range=(0,0.25))
        ],
        "pid": [
            Param(name="which_pid", type=str, values=[ "o", "orientation", "p", "position" ]),
            Param(name="Kp", type=float),
            Param(name="Ki", type=float),
            Param(name="Kd", type=float)
        ],
        "rtt_test": [
            Param(name="samples", type=int, default=1000),
            Param(name="delay_ms", type=float, default=16.67)
        ],
        "measure_angvel": [
            Param(name="steering", type=float, range=(-0.1,0.1)),
            Param(name="seconds", type=float, range=(1,10))
        ],
        "pos_goal_tolerance": [
            Param(name="distance", type=float, range=(0,1))
        ],
        "render": [
            Param(name="planes", type=bool),
            Param(name="meshes", type=bool)
        ],
        "map": [],
        "image": [
            Param(name="filepath", type=str)
        ],
        "get_view": []
    }

    def __init__(self, tasks: List[asyncio.Task], send_message: Callable[[BaseModel,], Awaitable[None]], image_viewer: ImageViewer):
        self._tasks = tasks
        self._send = send_message
        self._image_viewer = image_viewer

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
                if param.type not in [ str, int, float, bool ]:
                    raise ValueError(f"Command \"{command}\" has invalid type for parameter \"{param.name}\". Must be one of: str, int, float, or bool")

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
            elif command == "?" or command == "help":
                self._print_help()
            elif command == "drive":
                reverse = True if args["direction"][0] == "b" else False
                if args["units"] == "s":
                    await self._send(DriveForDurationMessage(reverse=reverse, seconds=args["amount"], speed=args["speed"]))
                else:
                    meters = args["amount"] * (0.01 if args["units"] == "cm" else 1.0)
                    await self._send(DriveForDistanceMessage(reverse=reverse, meters=meters, speed=args["speed"]))
                print("Sent drive command")
            elif command == "s" or command == "stop":
                await self._send(DriveForDurationMessage(reverse=False, seconds=1e-3, speed=0))
                print("Sent stop command")
            elif command == "rot":
                await self._send(RotateMessage(degrees=args["degrees"]))
                print("Sent rotate command")
            elif command == "df":
                await self._send(DriveForwardMessage(deltaMeters=args["delta_meters"]))
                print("Sent drive forward command")
            elif command == "watchdog":
                timeout = max(0, args["timeout_sec"])
                enabled = timeout > 0
                await self._send(WatchdogSettingsMessage(enabled=enabled, timeoutSeconds=timeout))
                if not enabled:
                    print("Sent request to disable watchdog")
                else:
                    print(f"Sent request to update watchdog timeout to {timeout} sec")
            elif command == "pwm":
                await self._send(PWMSettingsMessage(pwmFrequency=args["hz"]))
                print("Sent request to change PWM frequency")
            elif command == "throttle":
                await self._send(ThrottleMessage(minThrottle=args["min"], maxThrottle=args["max"]))
                print("Sent throttle value update")
            elif command == "pid":
                pid_names = { "o": "orientation", "orientation": "orientation", "p": "position", "position": "position" }
                which_pid = pid_names[args["which_pid"]]
                await self._send(PIDGainsMessage(whichPID=which_pid, Kp=args["Kp"], Ki=args["Ki"], Kd=args["Kd"]))
                print(f"Sent PID gain parametrs for \"{which_pid}\" controller")
            elif command == "rtt_test":
                num_samples = args["samples"]
                delay = args["delay_ms"] * 1e-3
                await self._send(HoverboardRTTMeasurementMessage(numSamples=num_samples, delay=delay, rttSeconds=[]))
                print("Sent hoverboard RTT test request")
            elif command == "measure_angvel":
                await self._send(AngularVelocityMeasurementMessage(steering=args["steering"], numSeconds=args["seconds"], angularVelocityResult=0))
                print("Sent angular velocity measurement request")
            elif command == "pos_goal_tolerance":
                await self._send(PositionGoalToleranceMessage(positionGoalTolerance=args["distance"]))
                print("Sent position goal tolerance update")
            elif command == "render":
                await self._send(RenderSceneGeometryMessage(planes=args["planes"], meshes=args["meshes"]))
                print("Sent scene mesh render selection update")
            elif command == "map":
                await self._send(RequestOccupancyMapMessage())
            elif command == "image":
                try:
                    with open(file=args["filepath"], mode="rb") as fp:
                        self._image_viewer.show(image=fp.read(), name=args["filepath"], height=600)
                except Exception as e:
                    print(f"Error: Failed to display image: {e}")
                    self._image_viewer.hide()
            elif command == "get_view":
                await self._send(RequestAnnotatedViewMessage())
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
        elif param.type == bool:
            value = False
            try:
                if arg.lower() in [ "on", "enable", "enabled", "true", "t" ]:
                    value = True
                elif arg.lower() in [ "off", "disable", "disabled", "false", "f" ]:
                    value = False
                else:
                    value = int(arg) != 0
            except ValueError:
                print(f"Error: Parameter \"{param.name}\" must be boolean value")
                return None
            return value
        else:
            # Assume str
            return arg

    def _cancel_tasks(self):
        print("Canceling tasks...")
        for task in self._tasks:
            task.cancel()


####################################################################################################
# Program Entry Point
####################################################################################################

if __name__ == "__main__":
    tasks = []
    navigation_ui = NavigationUI()
    image_viewer = ImageViewer()
    server = RoBartDebugServer(port=8000, navigation_ui=navigation_ui, image_viewer=image_viewer)
    console = CommandConsole(tasks=tasks, send_message=server.send_to_clients, image_viewer=image_viewer)
    loop = asyncio.new_event_loop()
    tasks.append(loop.create_task(server.run()))
    tasks.append(loop.create_task(console.run()))
    tasks.append(loop.create_task(navigation_ui.run(send_message=server.send_to_clients)))
    tasks.append(loop.create_task(image_viewer.run()))
    try:
        loop.run_until_complete(asyncio.gather(*tasks))
    except asyncio.exceptions.CancelledError:
        print("\nExited normally")
    except:
        print("\nExited due to uncaught exception")
