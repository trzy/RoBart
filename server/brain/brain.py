#
# TODO:
# -----
# - Render occupancy map and see if that is easier for Claude to parse
#   - Add a tool or a section for Claude to record landmarks and these can be printed in the 
#     occupancy map (for e.g., keeping track of search)
# - Need to make sure prompts tell robot to use landmark based navigation if possible otherwise
#   to use manual navigation to get out of sticky situations. Should be helped by trajectory images.
# - Agent often makes reference to compass directions but we need to give it a convention to follow
#   (e.g., north = decreasing Z, west=decreasing x)
# x Trajectory photos for backing out
#   - What if we always just pass in trajectory photos and remove explicit photo taking commands?
# - Return to landmark mode
#   - De-dupe landmarks (try to reuse landmarks rather than endlessly generating new ones)
#   - Memory section should once again be structured and include landmarks
# - Generate each LLM output section (MEMORY, PLAN, ACTIONS) by prompting each separately.
# - Run some experiments asking Claude to generate high-level strategies and then instructions that
#   can be used as a system prompt (e.g., can it come up with a grid search strategy and then
#   instructions for maintaining memory to accomplish that?).
#

import asyncio
import json
import os
import traceback
from typing import Awaitable, Callable, Dict, List, Optional, Tuple

from pydantic import BaseModel

from .claude import Message, think
from .block_parser import parse_blocks
from .image import decode_annotated_image, Image
from .logger import BrainLogger
from .occupancy_map import CoordUnit, MapAnnotation, RobotMarker, RenderOptions, render_occupancy_map
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
                # Time to summarize?
                messages = await _summarize(messages=messages, model=model)

                logger.log_input(messages)

                response = await think(
                    messages=messages,
                    system=SYSTEM_PROMPT,
                    model=model,
                    stop_sequences=[STOP_TAG],
                )
                logger.log_output(response)
                messages.append(Message(role="assistant", content=[response]))

                blocks = parse_blocks(response)
                tags = [b.tag for b in blocks]
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
                results_content, images = _format_results(msg=obs_msg, extra_results_content=server_results_content, log_dir=logger.step_directory)

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

def _create_occupancy_map(msg: ObservationsMessage) -> str:
    cells_wide = msg.mapCellsWide
    cells_deep = msg.mapCellsDeep
    last_visited = msg.lastVisited
    occupancy = msg.occupancy
    total = cells_wide * cells_deep

    # First pass: render visited cells as digits, unvisited as '.'
    grid = ['.'] * total

    visited = [t for t in last_visited if t >= 0]
    if visited:
        newest = max(visited)
        oldest = min(visited)
        time_range = newest - oldest

        for i in range(total):
            t = last_visited[i]
            if t >= 0:
                if time_range < 1e-6:
                    grid[i] = '0'
                else:
                    age = newest - t
                    digit = min(int(age / time_range * 9.999), 9)
                    grid[i] = str(digit)

    # Second pass: mark occupied cells as 'x'
    for i in range(total):
        if occupancy[i]:
            grid[i] = 'x'

    # Build row strings
    rows = []
    for z in range(cells_deep):
        start = z * cells_wide
        rows.append("".join(grid[start:start + cells_wide]))
    return "\n".join(rows)


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

def _format_results(msg: Optional[ObservationsMessage], extra_results_content: list, log_dir: str) -> Tuple[list, list]:
    open_tag = f"<{RESULT_SECTION_NAME}>"
    close_tag = f"</{RESULT_SECTION_NAME}>"
    
    images: List[Image] = []
    
    if msg is None:
        return [f"{open_tag}\nStep completed successfully.\n{close_tag}"], []
    
    if not msg.images:
        return [f"{open_tag}\n{msg.description}\n{close_tag}"], []
    
    # Description from robot and images
    label = "Image:" if len(msg.images) == 1 else "Images:"
    content = [f"{open_tag}\n{msg.description}\n{label}\n"]
    for annotated_image in msg.images:
        image = decode_annotated_image(annotated_image, coords=False)
        content.append(image)
        images.append(image)
        # Point locations are now rendered directly on the image as coord labels
        # if len(image.points) > 0:
        #     landmarks_text = "\nPoint locations:\n" + "\n".join([ f"pos=({point.worldPosition.x:.2f},{point.worldPosition.z:.2f})" for point in image.points ])
        #     content.append(landmarks_text)
    
    # Render occupancy map
    occupancy_map_render_options = RenderOptions(
        cells_wide=msg.mapCellsWide,
        cells_deep=msg.mapCellsDeep,
        occupancy=msg.occupancy,
        origin_x=msg.mapOriginX,
        origin_z=msg.mapOriginZ,
        cell_size=msg.mapCellSize,
        cell_pixels=8,
        last_visited=msg.lastVisited,
        robot=RobotMarker(position=msg.currentPosition, forward=msg.currentForward, radius_cells=1.5),
        output_path=os.path.join(log_dir, "occupancy.png")
    )
    occupancy_map = render_occupancy_map(opts=occupancy_map_render_options)
    occupancy_description = "\n".join([
        "Occupancy Map:",
        "blue=obstacle, red dot=robot (red line indicates forward dir), green=most recently visited cells (lighter is more recent)",
        f"cell width={msg.mapCellSize}, top left cell pos=({msg.mapOriginX + 0.5 * msg.mapCellSize:.1f},{msg.mapOriginZ + 0.5 * msg.mapCellSize:.1f}), bottom right cell pos=({msg.mapOriginX + (msg.mapCellsWide - 0.5) * msg.mapCellSize:.1f},{msg.mapOriginZ + (msg.mapCellsDeep - 0.5) * msg.mapCellSize:.1f})",
    ])
    content.append(occupancy_description)
    content.append(occupancy_map)
    
    # Text version
    # map_text = "\n".join([
    #     "Occupancy Map:",
    #     ".=navigable x=obstacle 0-9=heatmap of last visited positions (0 is now, 9 is longest ago)",
    #     f"cell width={msg.mapCellSize}, top left cell pos=({msg.mapOriginX + 0.5 * msg.mapCellSize:.1f},{msg.mapOriginZ + 0.5 * msg.mapCellSize:.1f}), bottom right cell pos=({msg.mapOriginX + (msg.mapCellsWide - 0.5) * msg.mapCellSize:.1f},{msg.mapOriginZ + (msg.mapCellsDeep - 0.5) * msg.mapCellSize:.1f})",
    #     _create_occupancy_map(msg=msg)
    # ])
    # content.append(map_text)

    # Visual trace
    # if msg.visualTrace:
    #     content.append(f"\nVisual trace ({len(msg.visualTrace)} samples during action execution):\n")
    #     for sample in msg.visualTrace:
    #         trace_img = Image(data=sample.imageJpegBase64, media_type="image/jpeg")
    #         trace_img = trace_img.resize(scale=0.25)
    #         p = sample.worldPosition
    #         content.append(f"t={sample.timestampSeconds:.2f}s pos=({p.x:.2f},{p.z:.2f})\n")
    #         content.append(trace_img)

    # Any additional content server wants to add
    if (len(extra_results_content) > 0):
        content += extra_results_content

    # End
    content.append(close_tag)
    return content, images

async def _summarize(messages: List[Message], model: str) -> List[Message]:
    # Time to summarize?
    num_assistant_messages = len([ message for message in messages if message.role == "assistant"])
    if num_assistant_messages < 3:
        return messages
    
    # Last message should be a user message, which we remove (we want to summarize all asssistant
    # messages prior)
    user_message = messages.pop()
    assert user_message.role == "user"
    assert messages[0].role == "user"   # very first one should be user message, too
    
    # Add instructions to summarize
    summary_prompt = """
Consolidate the conversation into a single output consisting of these sections: 
MEMORY, PLAN, INTERMEDIATE_RESPONSE, ACTIONS. 

IMPORTANT: In MEMORY, list ALL image numbers you have captured with their coordinates
and what they show. You can recall any image later using viewImages. Don't remove any
information we may need in the future.
"""
    messages.append(Message(role="user", content=[ summary_prompt ]))

    # Summarize
    print("\nSummarizing...\n")
    response = await think(
        messages=messages,
        system=SYSTEM_PROMPT,
        model=model,
        stop_sequences=[STOP_TAG],
    )
    assistant_message = Message(role="assistant", content=[ response ])

    # Reconstruct a smaller history consisting of first user message, summarized
    # assistant output, then the most recent user message we had
    return [ messages[0], assistant_message, user_message ]
