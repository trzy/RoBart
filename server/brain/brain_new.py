import asyncio
import json
import os
import traceback
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

from pydantic import BaseModel

from .claude import ParamType, ToolParameter, Tool, Message, think
from .block_parser import parse_blocks
from .image import decode_annotated_image, Image
from .streaming_logger import StreamingLogger
from .occupancy_map import CoordUnit, MapAnnotation, RobotMarker, RenderOptions, render_occupancy_map
from ..messages import ActionsMessage, ObservationsMessage, VisualTraceMessage


####################################################################################################
# Brain
#
# Drives the AI loop: submits instructions to Claude, dispatches actions to the robot, and waits
# for observations before continuing.
####################################################################################################

SYSTEM_PROMPT = """
You are RoBart, a mobile wheeled robot with the world's most capable AI that dutifully helps users.
Use the tools available to you to see the world, move about, and query stored information.

Create and maintain a plan. This should include a long-term strategy for solving your task. Break
this down further into sub-tasks as appropriate and keep track of them. Write this down your plan
and progress in <PLAN>...</PLAN> tags. Update this each time you complete a step. Maintain a sufficiently
detailed history of your actions to help you back track when you get stuck.

Maintain a memory of your environment, objects and areas you have seen, and spatial relationships
between them. Images will be labeled with numeric landmark points that remain consistent over time.
Your position and forward vector on the xz-plane will be given as vectors of (x,z). Maintain your 
observations and analysis in <MEMORY>...</MEMORY> sections and update these each time you have new
observations.

Give regular spoken updates to let people nearby know what you are trying to do next. These should
be 1-3 sentences and enclosed in <INTERMEDIATE_RESPONSE>...</INTERMEDIATE_RESPONSE> tags.

When you are finished, given a final spoken response (up to 5 sentences) in
<FINAL_RESPONSE>...</FINAL_RESPONSE> tags.
"""

class NewBrain:
    def __init__(self):
        self._send: Optional[Callable[[BaseModel], Awaitable[None]]] = None
        self._observations_queue: asyncio.Queue[ObservationsMessage] = asyncio.Queue()
        self._image_by_id: Dict[int, Image] = {}

    def set_send(self, send: Callable[[BaseModel], Awaitable[None]]):
        self._send = send

    async def on_observations_message(self, session, msg: ObservationsMessage, timestamp: float):
        await self._observations_queue.put(msg)

    async def on_visual_trace_message(self, session, msg: VisualTraceMessage, timestamp: float):
        print("[NewBrain] Received visual trace message: Ignoring (not implemented).")

    def _store_images(self, images: List[Image]):
        for image in images:
            self._image_by_id[image.id] = image

    def _process_observations(self, msg: Optional[ObservationsMessage]) -> List[str | Image]:
        if msg is None:
            return [ "Step completed successfully" ]
        
        images: List[Image] = []
        
        # Description from robot only
        if not msg.images:
            return [f"{msg.description}\n"]
    
        # Description and images
        label = "Image:" if len(msg.images) == 1 else "Images:"
        content = [f"{msg.description}\n{label}\n"]
        for annotated_image in msg.images:
            image = decode_annotated_image(annotated_image, coords=False)
            content.append(image)
            images.append(image)
        # if len(image.points) > 0:
        #     landmarks_text = "\nPoint locations:\n" + "\n".join([ f"pos=({point.worldPosition.x:.2f},{point.worldPosition.z:.2f})" for point in image.points ])
        #     content.append(landmarks_text)
    
        # Save images for future recall
        self._store_images(images=images)

        return content

    async def _tool_take_photo(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "takePhoto" }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg)
    
    async def _tool_scan_360(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "scan360" }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg)
    
    async def _tool_move(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "move", "distance": params["distance"] }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg)        
    
    async def _tool_move_to(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "moveTo", "pointNumber": params["pointNumber"] }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg)
    
    async def _tool_turn_in_place(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "turnInPlace", "degrees": params["degrees"] }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg)
    
    async def _tool_face_toward(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "faceToward", "pointNumber": params["pointNumber"] }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg)

    async def run(self, instructions: str, model: str = "claude-sonnet-4-6"):
        try:
            tools = [
                Tool(
                    name="takePhoto",
                    description="Take a photo",
                    parameters=[],
                    handler=self._tool_take_photo
                ),
                Tool(
                    name="scan360",
                    description="Turn 360 degrees and take multiple photos all around, useful for analyzing surroundings",
                    parameters=[],
                    handler=self._tool_scan_360

                ),
                Tool(
                    name="move",
                    description="Move forward or backward",
                    parameters=[
                        ToolParameter(name="distance", type=ParamType.NUMBER, description="Meters to move forward (positive) or backward (negative)")
                    ],
                    handler=self._tool_move
                ),
                Tool(
                    name="moveTo",
                    description="Move to a specific landmark point",
                    parameters=[
                        ToolParameter(name="pointNumber", type=ParamType.INTEGER, description="Landmark point to go to")
                    ],
                    handler=self._tool_move_to
                ),
                Tool(
                    name="turnInPlace",
                    description="Turn the robot in place",
                    parameters=[
                        ToolParameter(name="degrees", type=ParamType.NUMBER, description="Degrees to turn left (positive) or right (negative)")
                    ],
                    handler=self._tool_turn_in_place
                ),
                Tool(
                    name="faceToward",
                    description="Turn to face a landmark",
                    parameters=[
                        ToolParameter(name="pointNumber", type=ParamType.INTEGER, description="Landmark point to face")
                    ],
                    handler=self._tool_face_toward
                ),
            ]
            logger = StreamingLogger()
            messages = [Message(role="user", content=[f"<HUMAN_INPUT>{instructions}</HUMAN_INPUT>"])]
            while True:
                logger.next_step()
                for msg in messages:
                    logger.log_message(msg)

                response = await think(
                    messages=messages,
                    system=SYSTEM_PROMPT,
                    model=model,
                    tools=tools,
                    on_message=logger.log_message,
                )
                messages.extend(response.messages)

                #TODO: this is broken because there are no more turns!

                blocks = parse_blocks(response.text)
                tags = [b.tag for b in blocks]
                if "FINAL_RESPONSE" in tags:
                    break

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
