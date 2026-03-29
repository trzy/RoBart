#TODO:
#   - Summarization
#   - Always include trajectory photos
#   - De-dupe landmarks (that is, reuse landmarks if possible when we already have ones near to newly-generated ones)
#   - Transmit occupancy maps, including one showing where we have already been in some color coded
#     way (darker color more distance, brighter more recent). Be able to place landmarks (from 
#     memory?) into map as well, and maybe annotate with some positions, uniformly distributed.

import asyncio
import json
import traceback
from typing import Awaitable, Callable, Dict, List, Optional, Tuple

from pydantic import BaseModel

from .claude import Message, think
from .block_parser import parse_blocks
from .image import decode_annotated_image, Image
from .logger import BrainLogger
from .prompts import SYSTEM_PROMPT
from ..messages import ActionsMessage, ObservationsMessage, VisualTraceMessage

RESULT_SECTION_NAME = "RESULTS" #"OBSERVATIONS"
STOP_TAG = f"<{RESULT_SECTION_NAME}>"


####################################################################################################
# Brain
#
# Drives the AI loop: submits instructions to Claude, dispatches actions to the robot, and waits
# for observations before continuing.
####################################################################################################

class Brain:
    def __init__(self):
        self._send: Optional[Callable[[BaseModel], Awaitable[None]]] = None
        self._observations_queue: asyncio.Queue[ObservationsMessage] = asyncio.Queue()
        self._image_by_id: Dict[int, Image] = {}

    def set_send(self, send: Callable[[BaseModel], Awaitable[None]]):
        self._send = send

    async def on_observations_message(self, session, msg: ObservationsMessage, timestamp: float):
        await self._observations_queue.put(msg)

    async def on_visual_trace_message(self, session, msg: VisualTraceMessage, timestamp: float):
        await handle_visual_trace_message(msg=msg, send=self._send)

    def _store_images(self, images: List[Image]):
        for image in images:
            self._image_by_id[image.id] = image
    
    def _handle_server_actions(self, actions: List[str]) -> list:
        content = []
        for action_str in actions:
            try:
                action = json.loads(action_str)
                if action["type"] == "viewImages":
                    for id in action["imageNumbers"]:
                        image = self._image_by_id.get(id)
                        if image is not None:
                            content.append(image)
                        else:
                            print(f"Error: Unable to lookup image id={id}")
            except Exception as e:
                print(f"Error: Unable to process action: {action_str}, reason: {e}")
                traceback.print_exc()
        return content

    async def run(self, instructions: str, model: str = "claude-sonnet-4-6"):
        try:
            logger = BrainLogger()
            messages = [Message(role="user", content=[f"<HUMAN_INPUT>{instructions}</HUMAN_INPUT>"])]
            while True:
                logger.log_input(messages)

                response = await think(
                    messages=messages,
                    system=SYSTEM_PROMPT,
                    model=model,
                    stop_sequences=[STOP_TAG],
                )
                logger.log_output(response)

                blocks = parse_blocks(response)
                tags = [b.tag for b in blocks]

                messages.append(Message(role="assistant", content=[response]))

                if "FINAL_RESPONSE" in tags:
                    break

                actions = _extract_actions(blocks)

                # Send actions to robot
                if actions and self._send:
                    await _send_actions(self._send, actions)
                    obs_msg = await _wait_for_observations(self._observations_queue)
                else:
                    obs_msg = None

                # Handle any actions that are designed to be handled here
                server_results_content = self._handle_server_actions(actions=actions)
                
                # Convert response from robot along with server action results to a single results
                # section
                results_content, images = _format_results(msg=obs_msg, extra_results_content=server_results_content)

                # Images from the robot are stored
                self._store_images(images=images)

                messages.append(Message(role="user", content=results_content))
        except Exception as e:
            print(f"Error: Exception caught: {e}")
            traceback.print_exc()


####################################################################################################
# Visual Trace Test
####################################################################################################

async def handle_visual_trace_message(msg: VisualTraceMessage, send: Optional[Callable[[BaseModel], Awaitable[None]]]):
    images = [Image(data=s.imageJpegBase64, media_type="image/jpeg") for s in msg.entries]

    print(f"\nVisualTrace: received {len(images)} sample(s)")
    for i, (sample, img) in enumerate(zip(msg.entries, images)):
        w_original, h_original = img.size
        scale = 0.25
        images[i] = img.resize(scale=scale)
        w, h = images[i].size
        print(f"  [{i}] t={sample.timestampSeconds:.2f}s  {w_original}x{h_original} -> {w}x{h}")

    system = """
You are a specialized agent tasked with analyzing a robot movement trajectory. Your audience is the 
navigation and control agent that produced the trajectory. 

The following move commands are supported by the robot:

    move: Moves the robot forward or backward in a straight line. Used only when the ground is visible in the current image or if stuck and needing to take corrective action using small distances.
        Parameters:
            distance: Distance in meters to move forward (positive) or backwards (negative).

    moveTo: Moves in a straight line to a specific navigable point from the photos in the most recent <OBSERVATIONS> block. Use with caution, ensure point is recently visible and no floor obstructions or nearby furniture exist. RoBart's orientation may be unpredictable so if a photo is needed at the destination, it is a good idea to scan around after arrival.
        Parameters:
            pointNumber: Integer number of the navigable point to move to.

    turnInPlace: Turns the robot in place by a relative amount.
        Parameters:
            degrees: Degrees to turn left (positive) or right (negative).

    faceToward: Turn toward an annotated navigable point from the most recent <OBSERVATIONS> block.
        Parameters:
            pointNumber: Integer number of the navigable point to face.

    Examples:
        [ { "type": "turnInPlace", "degrees": 30 }, { "type": "move", "distance": -1.5 } ]
        [ { "type": "move", "distance": 5 } ]

For each query output:

1. 1-3 sentences determining whether it succeeded or not and if not, why it failed.
2. If the tajectory failed, 1-3 sentences thinking about how to maneuver successfully or to a more 
   favorable location from which to proceed.
3. If the trajectory failed, generate a trajectory that precisely backtracks. Place a list of JSON
   actions between <ACTIONS></ACTIONS> tags.

Keep your output concise and avoid extraneous formatting.
"""
    content = []
    #content = ["The following images were captured during a robot traversal.\n"]
    for sample, img in zip(msg.entries, images):
        p = sample.worldPosition
        content.append(f"t={sample.timestampSeconds:.2f}s  pos=({p.x:.2f}, {p.y:.2f}, {p.z:.2f})\n")
        content.append(img)
    messages = [Message(role="user", content=content)]
    response = await think(messages=messages, system=system, model="claude-sonnet-4-6")
    print(f"\n{response}")

    # Extract and send actions, if any
    blocks = parse_blocks(response)
    actions = _extract_actions(blocks)
    if actions and send:
        await _send_actions(send, actions)
        print("Sent actions")



####################################################################################################
# Helpers
####################################################################################################

def _extract_actions(blocks) -> list[str]:
    for b in blocks:
        if b.tag == "ACTIONS":
            try:
                action_list = json.loads(b.content.strip())
                return [json.dumps(action) for action in action_list]
            except (json.JSONDecodeError, TypeError) as e:
                print(f"Warning: failed to parse ACTIONS JSON: {e}")
                return []
    return []

async def _send_actions(send, actions: list[str]):
    await send(ActionsMessage(actions=actions))

async def _wait_for_observations(queue: asyncio.Queue) -> ObservationsMessage:
    return await queue.get()

def _format_results(msg: Optional[ObservationsMessage], extra_results_content: list) -> Tuple[list, list]:
    open_tag = f"<{RESULT_SECTION_NAME}>"
    close_tag = f"</{RESULT_SECTION_NAME}>"
    images: List[Image] = []
    if msg is None:
        return [f"{open_tag}\nStep completed successfully.\n{close_tag}"], []
    if not msg.images:
        return [f"{open_tag}\n{msg.description}\n{close_tag}"], []
    label = "Image:" if len(msg.images) == 1 else "Images:"
    content = [f"{open_tag}\n{msg.description}\n{label}\n"]
    for annotated_image in msg.images:
        image = decode_annotated_image(annotated_image)
        content.append(image)
        images.append(image)
        if len(image.points) > 0:
            landmarks_text = "\nPoint locations:\n" + "\n".join([ f"pos=({point.worldPosition.x:.2f},{point.worldPosition.z:.2f})" for point in image.points ])
            content.append(landmarks_text)
    if (len(extra_results_content) > 0):
        content += extra_results_content
    content.append(close_tag)
    return content, images
