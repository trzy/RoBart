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
from ..messages import ActionsMessage, ObservationsMessage, VectorXZ, VisualTraceMessage


####################################################################################################
# Brain
#
# Drives the AI loop: submits instructions to Claude, dispatches actions to the robot, and waits
# for observations before continuing.
####################################################################################################

SYSTEM_PROMPT = """
You are RoBart, a mobile wheeled robot with the world's most capable AI that dutifully helps users.
Use the tools available to you to see the world, move about, and query stored information.

# Planning

Create and maintain a plan. This should include a long-term strategy for solving your task. Break
this down further into sub-tasks as appropriate and keep track of them. Write down your plan
and progress in <PLAN>...</PLAN> tags. Update this each time you complete a step and re-state it in
its entirety so that the latest copy is the current plan-of-record.

## Format of a Good Plan

    # [Short, action-oriented description]

    This plan is a living document. The sections "Progress", "State", "Outcomes & Retrospective",
    must be kept up to date as you proceed.

    ## Objective

    Explain in a few sentences the overall task objective and the condition for which it will be
    considered complete.

    ## Procedure

    Describe the overall procedure or algorithm you will use to perform the task. You may use
    pseudo-code, lists, and write multiple sub-sections as desired. If you will need to keep track
    of state or observations, describe clearly their format and rules for updating them.
    
    ## Progress

    Record granular progress as you perform the task using a list with checkboxes.

    ## State

    Record every decision made while working on the task and any state information necessary to the
    overall state of the task and current sub-task. Any information that your procedure or algorithm
    needs to track should be recorded here to help long- and short-term decision making at each step.

    ## Outcomes & Retrospective

    Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare the
    result against the original purpose and determine whether you are making progress or getting stuck.

# Feedback to People

Give regular spoken updates to let people nearby know what you are trying to do next. These should
be 1-3 sentences and enclosed in <INTERMEDIATE_RESPONSE>...</INTERMEDIATE_RESPONSE> tags.

# Stopping Condition1

When you are finished, given a final spoken response (up to 5 sentences) in
<FINAL_RESPONSE>...</FINAL_RESPONSE> tags.
"""

class NewBrain:
    def __init__(self):
        self._send: Optional[Callable[[BaseModel], Awaitable[None]]] = None
        self._observations_queue: asyncio.Queue[ObservationsMessage] = asyncio.Queue()
        self._image_by_id: Dict[int, Image] = {}
        self._memory: Dict[int, str] = {}

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

        # Collect unique point locations across all images
        points_by_id = _collect_points(images)
        if points_by_id:
            content.append("\Landmark locations:\n" + "\n".join(
                f"  {pid}: pos=({pos.x:.2f},{pos.z:.2f})" for pid, pos in sorted(points_by_id.items())
            ))

        # Save images for future recall
        self._store_images(images=images)

        return content
    
    async def _tool_update_memories(self, params: Dict[str, Any]) -> List[str | Image]:
        memories = params["memories"]
        for memory in memories:
            pointNumber = memory["pointNumber"]
            description = memory["description"]
            if len(description) == 0:
                if pointNumber in self._memory:
                    del self._memory[pointNumber]
            else:
                self._memory[pointNumber] = description
        memory_text = "<MEMORY>\n" + "\n".join([ f"{pointNumber}: {description}" for pointNumber, description in self._memory.items() ]) + "\n</MEMORY>"
        return [ memory_text ]

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
        print(f"Using model: {model}")

        try:
            tools = [
                # Tool(
                #     name="updateMemory",
                #     description="Update memory",
                #     parameters=[
                #         ToolParameter(
                #             name="memories",
                #             type=ParamType.ARRAY,
                #             description="Array of landmarks to add/update/remove",
                #             required=True,
                #             properties=[ 
                #                 ToolParameter(name="pointNumber", type=ParamType.INTEGER, description="Landmark number"), 
                #                 ToolParameter(name="description", type=ParamType.STRING, description="Description of landmark (empty string to delete from memory)"),
                #             ],
                #             array_type=ParamType.OBJECT
                #         )
                #     ],
                #     handler=self._tool_update_memories
                # ),
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

                if response.succeeded:
                    messages.extend(response.messages)
                else:
                    print(f"Error: Model failure: {response.text}")
                    break

                #TODO: this is broken because there are no more turns!

                blocks = parse_blocks(response.text)
                tags = [b.tag for b in blocks]
                if "FINAL_RESPONSE" in tags:
                    break

        except Exception as e:
            print(f"Error: Exception caught: {e}")
            traceback.print_exc()


####################################################################################################
# Helpers
####################################################################################################

def _collect_points(images: List[Image]) -> Dict[int, VectorXZ]:
    """Collect unique points across all images, keyed by point ID."""
    points_by_id: Dict[int, VectorXZ] = {}
    for image in images:
        for point in image.points:
            points_by_id[point.id] = point.worldPosition
    return points_by_id