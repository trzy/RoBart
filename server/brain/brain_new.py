import asyncio
import json
import math
import os
import traceback
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

from pydantic import BaseModel

from enum import Enum
from .llm import ParamType, ToolParameter, Tool, ToolResult, Message, ThinkingEffort, think, count_tokens, context_window_size
from .block_parser import parse_blocks
from .image import decode_annotated_image, Image, pil_to_base64_png
from .streaming_logger import StreamingLogger
from .occupancy_map import CoordUnit, MapAnnotation, RobotMarker, RenderOptions, render_occupancy_map
from ..messages import ActionsMessage, ObservationsMessage, VectorXZ, VisualTraceMessage
from ..tools.generate_maps import Map, generate_images


####################################################################################################
# Brain
#
# Drives the AI loop: submits instructions to Claude, dispatches actions to the robot, and waits
# for observations before continuing.
####################################################################################################

# TODO: summarization periodically, also remove images frequently N messages prior
# TODO: we need to specify what angles 360 degree photos are in relative to the end position to
#.      encourage the agent to turn back toward an image
# TODO: add a tool to rewind history until time=t, which means giving the time each update.

# TODO: seems hopeless to trust the model to stop and re-think things with each update. I think 
#       we should try an explicit re-act like framework again. We may need to explicitly prompt it
#       each step to update the plan, etc. We may also want parallel conversation threads, e.g. one
#       that observes and does nothing more than describe the space and all objects. Or, create very
#       high level tools like "make_observations" and "move", with separate threads with finer-grained
#       tooling handling the details (and of course maintaining some state between these threads).
#
#       For example, for each image, we might need to invoke a sub-agent with some general context
#       about the task (e.g., the user input itself), current descriptions of given landmarks, and
#       ask it to update landmark description and generate new ones for new landmarks.
#
#       We could also have multiple different high level loops, such as EXPLORE/SEARCH, MOVE_TO,
#       FREEFORM, INTERACT, etc. MOVE_TO could be a landmark, or it could be formulated as an 
#       object in an image, with the image passed to the sub-agent. 
#
#       Perhaps an initial planning agent that, given a series of tools, comes up with which tools
#       will be needed, or a plan in terms of modes to execute.
#
#       This project shows how to plan and break down into tasks, albeit in a very simple fashion:
#       https://github.com/open-multi-agent/open-multi-agent/blob/591ce6da94cc35d3d2e6af406cc238ade64db3f9/src/orchestrator/orchestrator.ts#L1520
#
#       We may need specialized agents.
#
#       EXPLORE mode might render both a very coarse grid-search map and more detailed occupancy
#       maps of each cell to search. Once thoroughly investigated, mark it and move on. During 
#       investigation of a grid cell, we may wander into another.

# IDEA: New architecture
#   - based around observation events. Any time we see anything novel and noteworthy, we should 
#     store it: landmarks and general observations.
#       - We can perhaps create a better memory tool. If objects are mentioned as interesting, we
#         could then run another prompt for further analysis (extracting positions, etc.)
#           - Should this be a separate agent with system prompt?
#       - After each of these observations, use a prompt to summarize everything into a new plan
#           - Should this be a separate agent with system prompt to create plan, also having tools
#             to look up previous
#           - What do we want to get out of these planning steps? Hopefully induce LLM to think about
#             what it has just observed and determine when it is observing the same object again.
#       - Should we get rid of landmark system and just use angles?
#       - Explore polar coordinates from map origin as a way to make landmarks more interpretable?
#   - The LLM often overshoots and it seems to realize this. Should we ask it to give an update about
#.    whether it is confused or surprised, and then run another conversation thread with previous
#.    photos to strategize how to recover.
#   - What do we do about situations where the agent is moving toward an object but then gets 
#     distracted by another object (e.g., first identifies and moves toward green barrel, does a 
#     scan and gets disoriented and then pursues orange barrels further away)? I feel like these 
#     should be tracked explicitly as sub-tasks and objects should be localized as precisely as 
#     possible early on, with this estimate refined.
#
# Observation: 
#   - Model seems pretty good at navigating top-down text maps. Let's try some more standalone
#     experiments involving rendered text maps and navigation around them. Can we devise a system
#     where a navigation mode uses such a coarse map and records memories and state to intelligently
#     navigate? What about if it is a picture of a map (as we have now) with landmarks rendered all
#     over it for facilitating navigation? Can we have a zoomed in view of each cell?

SYSTEM_PROMPT = """
You are RoBart, an advanced mobile wheeled robot AI agent that dutifully helps users.
Use the tools available to you to see the world, move about, and query stored information. Diligently
maintain information about where you have moved and why, and keep track of intermediate and long-term
objectives.

<personality>
You are cheerful and helpful. You always speak in very short, concise sentences.
</personality>

<navigation>
An overhead occupancy map will be updated with each action you take. Empty space indicates either
unobstructed floor space or unexplored space. Blue indicates an obstruction. Green indicates cells 
that you have traversed. Your position and heading is indicated by a red chevron pointing in the 
direction you are currently facing. North is decreasing z and west is decreasing x. 

Landmark point numbers are rendered atop the map. These appear in photos you take as well. They 
indicate unobstructed locations on the ground. Use them for navigation and as reference points. 

As you explore the world, take note of objects of interest and remember their locations via the 
nearest landmarks. Identify different rooms or functional parts of the space and note the landmarks
associated with them so that you can later move between them if required by a task. Use the 
saveLandmarks tool to store detailed information describing what is at or nearby a landmark, and what
area of the space it is in. You can later search for landmarks semantically with findLandmarks or
recall a specific landmark with describeLandmarks.
</navigation>

<thinking_and_planning>
Think before you act. Make note of your overall objective as well as the criteria for determining success. 
Evaluate whether each step you took was successful and if not, adjust your planning accordingly.

As you explore and learn about your environment, create sub-goals in terms of areas you need to move to or search.
Keep track of regions that have been unexplored in case you need to return to them later. Each time
the occupancy map changes, update the plan and sub-goals.

Review past steps to determine whether you are stuck and need to back out and retry.
</thinking_and_planning>

<movement>
You can move and turn in three ways:

1. Landmark point numbers. These appear in images and remain stable. You can move to or turn toward them.
2. Image numbers. If you want to return exactly to where a photo was taken from, use this. If you haven't moved from a photo position but have turned, this will turn back to that viewpoint. 
3. Directly. You can specify meters to move forward or backward or angles to turn.

When you find yourself repeatedly finding and then losing sight of a target, try switching to a strategy
of finer adjustments with direct movement. You can return to previous known good image poses and then
try finer adjustments.
</movement>

<videos>
When performing movements, video frames of the motion will be provided. Use these to determine if
an object has been overshot, an obstacle has been hit, etc. These can help determine whether you
need to make fine adjustments.
</videos>

<feedback>
Regularly give spoken updates to let people nearby know what you are trying to do next using the 
speak tool. When the task is complete, use this tool to deliver a final response.
</feedback>
"""

class NewBrain:
    def __init__(self):
        self._send: Optional[Callable[[BaseModel], Awaitable[None]]] = None
        self._observations_queue: asyncio.Queue[ObservationsMessage] = asyncio.Queue()

        # This state is reset on each run() call
        self._model = "claude-sonnet-4-6"
        self._image_by_id: Dict[int, Image] = {}
        self._landmark_positions_by_id: Dict[int, VectorXZ] = {}
        self._landmark_descriptions: Dict[int, str] = {}
        self._overhead_map: Optional[Map] = None
        self._final_response_delivered = False

    def set_send(self, send: Callable[[BaseModel], Awaitable[None]]):
        self._send = send

    async def on_observations_message(self, session, msg: ObservationsMessage, timestamp: float):
        await self._observations_queue.put(msg)

    async def on_visual_trace_message(self, session, msg: VisualTraceMessage, timestamp: float):
        print("[NewBrain] Received visual trace message: Ignoring (not implemented).")

    def _store_images(self, images: List[Image]):
        for image in images:
            self._image_by_id[image.id] = image

    def _store_landmarks(self, images: List[Image]):
        for image in images:
            for point in image.points:
                self._landmark_positions_by_id[point.id] = point.worldPosition

    def _process_observations(self, msg: Optional[ObservationsMessage], include_visual_trace: bool) -> List[str | Image]:
        if msg is None:
            return [ "\n<command_result>Step completed successfully<command_result>\n" ]
        
        content = [ "\n<command_result>\n" ]
        images: List[Image] = []

        # Description
        content.append(f"{msg.description}\n")

        # Photos
        if len(msg.images) > 0:
            content.append("\n<photos>\n")
            
            # Photos
            for annotated_image in msg.images:
                image = decode_annotated_image(annotated_image, coords=False)
                content.append(image)
                content.append(_get_angle_to_image(image=image, currentForward=msg.currentForward))
                images.append(image)

            # Collect unique landmark points and list them
            points_by_id = _collect_points(images)
            # if points_by_id:
            #     content.append("\nLandmark positions:\n" + "\n".join(f"  {pid}: pos=({pos.x:.2f},{pos.z:.2f})" for pid, pos in sorted(points_by_id.items())))

            content.append("\n</photos>\n")

        # Visual trace
        if include_visual_trace and msg.visualTrace:
            trace_samples = _resample(msg.visualTrace, max_samples=5)
            content.append("\n<video>\nVideo of action:\n")
            for sample in trace_samples:
                trace_img = Image(data=sample.imageJpegBase64, media_type="image/jpeg")
                trace_img = trace_img.resize(scale=0.25)
                p = sample.worldPosition
                content.append(f"t={sample.timestampSeconds:.2f}s pos=({p.x:.2f},{p.z:.2f})\n")
                content.append(trace_img)
            content.append("\n</video>\n")

        # Save images for future recall
        self._store_images(images=images)

        # Save all landmarks
        self._store_landmarks(images=images)

        # DEBUG: Render occupancy map with all landmarks as annotations
        occupancy_map_options = RenderOptions(
            cells_wide = msg.mapCellsWide,
            cells_deep = msg.mapCellsDeep,
            occupancy = msg.occupancy,
            origin_x = msg.mapOriginX,
            origin_z = msg.mapOriginZ,
            cell_size = msg.mapCellSize,
#            image_width = 512,
            cell_pixels=10,
            annotations = [ MapAnnotation(x=position.x, z=position.z, label=str(id)) for id, position in self._landmark_positions_by_id.items() ],
            last_visited = msg.lastVisited,
            heatmap_recent_color = (0, 255, 0),
            heatmap_old_color = (0, 255, 0),
            robot = RobotMarker(position=msg.currentPosition, forward=msg.currentForward, radius_cells=2), 
            output_path = "occupancy_map.png"
        )
        occupancy_map_image = render_occupancy_map(opts=occupancy_map_options)
        content.append("\n<occupancy_map>\n")
        content.append(occupancy_map_image)
        content.append("\n</occupancy_map>\n")

        # Overhead map
        # self._overhead_map, overhead_map_image = _update_overhead_map(map=self._overhead_map, observations_msg=msg)
        # content.append("\n<overhead_map>\n")
        # content.append(overhead_map_image)
        # content.append("\n</overhead_map>\n")

        # Terminate block and return
        content.append("\n</command_result>\n")
        return content
    
    async def _compact_history(self, messages: List[Message]) -> List[Message]:
        messages = _remove_all_but_last_video_frames(messages=messages)
        messages = _remove_images_from_messages(messages=messages, keep=3)

        # Summarize if time to do so. We include the very first user message plus the summary.
        #TODO: we should also count tools
        num_tokens = await count_tokens(messages=messages, system=SYSTEM_PROMPT, model=self._model)
        max_tokens = await context_window_size(model=self._model)
        context_window_usage_pct = 100.0 * (num_tokens / max_tokens)
        if num_tokens > 10000: #context_window_usage_pct >= 50:
            print(f"\nContext window usage is {context_window_usage_pct:.1f}%, compacting...\n")
            original_user_message = messages[0]
            summary_assistant_message = await _produce_summary(messages=messages)
            continue_user_message = Message(role="user", content=[ "Continue from the plan's next step" ])   # assistant prefill not supported, must end with a user message
            messages = [ original_user_message, summary_assistant_message, continue_user_message ]

        return messages
    
    async def _tool_save_landmarks(self, params: Dict[str, Any]) -> List[str | Image]:
        landmarks = params["landmarks"]
        for entry in landmarks:
            pid = entry["pointNumber"]
            desc = entry["description"]
            if len(desc) == 0:
                self._landmark_descriptions.pop(pid, None)
            else:
                self._landmark_descriptions[pid] = desc
        return [f"Saved {len(landmarks)} landmark update(s). Total stored: {len(self._landmark_descriptions)}."]

    async def _tool_describe_landmarks(self, params: Dict[str, Any]) -> List[str | Image]:
        point_numbers = params["pointNumbers"]
        lines = []
        for pid in point_numbers:
            desc = self._landmark_descriptions.get(pid)
            if desc is None:
                lines.append(f"{pid}: (no description stored)")
            else:
                lines.append(f"{pid}: {desc}")
        return ["<LANDMARKS>\n" + "\n".join(lines) + "\n</LANDMARKS>"]

    async def _tool_find_landmarks(self, params: Dict[str, Any]) -> List[str | Image]:
        query = params["query"]
        if not self._landmark_descriptions:
            return ["<LANDMARKS>\n(no landmarks stored)\n</LANDMARKS>"]

        catalog = "\n".join(
            f"{pid}: {desc}" for pid, desc in sorted(self._landmark_descriptions.items())
        )
        search_system = (
            "You are a landmark search assistant. You are given a list of numbered landmarks and "
            "a user query. Return every landmark that matches the query by meaning (not exact word "
            "match), formatted as 'number: description' lines. "
            "If nothing matches, say 'no matching landmarks found'."
        )
        search_user = f"<LANDMARKS>\n{catalog}\n</LANDMARKS>\n\nQuery: {query}"
        result = await think(
            messages=[Message(role="user", content=[search_user])],
            system=search_system,
            model=self._model,
        )
        if not result.succeeded:
            return [f"Error searching landmarks: {result.text}"]
        return [result.text]

    async def _tool_take_photo(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "takePhoto" }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg, include_visual_trace=False)
    
    async def _tool_scan_360(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "scan360" }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg, include_visual_trace=False)
    
    async def _tool_move(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "move", "distance": params["distance"] }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg, include_visual_trace=True)        
    
    async def _tool_move_to(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "moveTo", "pointNumber": params["pointNumber"] }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg, include_visual_trace=True)
    
    async def _tool_move_to_image(self, params: Dict[str, Any]) -> List[str | Image]:
        # Look up image
        id = params["imageNumber"]
        image = self._image_by_id.get(id)
        if image is None:
            return [ f"No image_{id} found in memory" ]
        
        # Create action to move to position and orientation of image
        action = { "type": "moveToLocation", "x": image.position.x, "z": image.position.z, "forwardX": image.forward.x, "forwardZ": image.forward.z }
        msg = ActionsMessage(actions = [ json.dumps(action) ])

        # Send
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg, include_visual_trace=True)
    
    async def _tool_turn_in_place(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "turnInPlace", "degrees": params["degrees"] }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg, include_visual_trace=True)
    
    async def _tool_face_toward(self, params: Dict[str, Any]) -> List[str | Image]:
        action = { "type": "faceToward", "pointNumber": params["pointNumber"] }
        msg = ActionsMessage(actions=[ json.dumps(action) ])
        await self._send(msg)
        obs_msg = await self._observations_queue.get()
        return self._process_observations(msg=obs_msg, include_visual_trace=True)
    
    async def _tool_speak(self, params: Dict[str, Any]) -> List[str | Image]:
        print(f"RoBart says: {params['text']}")
        if params["final"]:
            self._final_response_delivered = True
            print("RoBart is finished.")
            return [ "RoBart is finished." ]
        return [ "RoBart spoke." ]

    async def run(self, instructions: str, model: str = "claude-sonnet-4-6"):
        print(f"Using model: {model}")

        # Reset state
        self._model = model
        self._image_by_id: Dict[int, Image] = {}
        self._landmark_descriptions: Dict[int, str] = {}
        self._overhead_map: Optional[Map] = None
        self._final_response_delivered = False

        try:
            tools = [
                Tool(
                    name="saveLandmarks",
                    description="Save descriptions for one or more landmark point numbers. Use this to remember objects, locations, or features tied to landmarks you have seen. Pass an empty description to forget a landmark.",
                    parameters=[
                        ToolParameter(
                            name="landmarks",
                            type=ParamType.ARRAY,
                            description="Array of landmarks to save/update/remove",
                            required=True,
                            properties=[
                                ToolParameter(name="pointNumber", type=ParamType.INTEGER, description="Landmark number"),
                                ToolParameter(name="description", type=ParamType.STRING, description="Description of the landmark (empty string to forget)"),
                            ],
                            array_type=ParamType.OBJECT,
                        ),
                    ],
                    handler=self._tool_save_landmarks,
                ),
                Tool(
                    name="findLandmarks",
                    description="Semantically search saved landmarks. Provide a natural-language query and get back the landmark numbers and descriptions that match.",
                    parameters=[
                        ToolParameter(name="query", type=ParamType.STRING, description="Natural-language search query"),
                    ],
                    handler=self._tool_find_landmarks,
                ),
                Tool(
                    name="describeLandmarks",
                    description="Recall the saved descriptions for specific landmark numbers.",
                    parameters=[
                        ToolParameter(
                            name="pointNumbers",
                            type=ParamType.ARRAY,
                            description="Landmark numbers to recall",
                            required=True,
                            array_type=ParamType.INTEGER,
                        ),
                    ],
                    handler=self._tool_describe_landmarks,
                ),
                Tool(
                    name="speak",
                    description="Speak out loud. Use this to inform nearby people of what you are about to do and deliver final responses. Be direct and concise because this will be spoken.",
                    parameters=[
                        ToolParameter(name="text", type=ParamType.STRING, description="Text to speak"),
                        ToolParameter(name="final", type=ParamType.BOOLEAN, description="If true, we are finished and speaking our final response"),
                    ],
                    handler=self._tool_speak
                ),
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
                    handler=self._tool_move,
                    rewrite_history=self._compact_history
                ),
                Tool(
                    name="moveTo",
                    description="Move to a specific landmark point",
                    parameters=[
                        ToolParameter(name="pointNumber", type=ParamType.INTEGER, description="Landmark point to go to")
                    ],
                    handler=self._tool_move_to,
                    rewrite_history=self._compact_history
                ),
                Tool(
                    name="moveToImage",
                    description="Move to location and orientation where image was taken",
                    parameters=[
                        ToolParameter(name="imageNumber", type=ParamType.INTEGER, description="Number of image whose location to go to")
                    ],
                    handler=self._tool_move_to_image,
                    rewrite_history=self._compact_history
                ),
                Tool(
                    name="turnInPlace",
                    description="Turn the robot in place",
                    parameters=[
                        ToolParameter(name="degrees", type=ParamType.NUMBER, description="Degrees to turn left (positive) or right (negative)")
                    ],
                    handler=self._tool_turn_in_place,
                    rewrite_history=self._compact_history
                ),
                Tool(
                    name="faceToward",
                    description="Turn to face a landmark",
                    parameters=[
                        ToolParameter(name="pointNumber", type=ParamType.INTEGER, description="Landmark point to face")
                    ],
                    handler=self._tool_face_toward,
                    rewrite_history=self._compact_history
                ),
            ]
            
            logger = StreamingLogger()

            messages = [Message(role="user", content=[f"<HUMAN_INPUT>{instructions}</HUMAN_INPUT>"])]

            while not self._final_response_delivered:
                logger.next_step()
                for msg in messages:
                    logger.log_message(msg, all_messages=messages)

                response = await think(
                    messages=messages,
                    system=SYSTEM_PROMPT,
                    model=model,
                    thinking=ThinkingEffort.NONE,#ThinkingEffort.HIGH,
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
# Compaction
####################################################################################################

#TODO: How do Codex, OpenClaw, and Claude Code do this? Do they compact everything into a user 
#      message to avoid assistant prefill? Or do they compact up to the last user message only?

SUMMARIZATION_SYSTEM_PROMPT = """
You are RoBart, an advanced mobile wheeled robot AI agent that dutifully helps users.

<capabilities>
You can move, turn, and photograph your environment. 
</capabilities>

<building_spatial_awareness>
Landmark points are given in images. These represent unobstructed points on the ground you can 
navigate to, although reachability is not always guaranteed. The points stay stable. Use the memory
tools to save points of interest that you see. They can be recalled later. Describe any interesting
objects, locations, and transition points between locations in terms of landmark points.

Use the provided overhead grid map to keep track of where you have explored. Cells are denoted by
coordinates like A1 and G5. Track these in your planning but to actually navigate to a neighboring cell,
you need to use landmark points or manually track direction. You can ask for any landmark to be 
rendered on the grid map to orient yourself better. Rendering specific landmarks of interest atop
the grid can be used strategically to give you a better sense of how objects and points of interest
are laid out spatially relative to you and each other.

North is decreasing z and west is decreasing x.
</building_spatial_awareness>
"""

SUMMARIZATION_USER_PROMPT = """
\nHere is a plan template:

<PLAN>
    <objective>
        Explain in a few sentences the overall task objective and the condition for which it will be
        considered complete.
    </objective>

    <procedure>
        Describe the overall procedure or algorithm you will use to perform the task. List the 
        tools and capabilities that will be helpful. Use pseudo-code, lists, and write multiple
        sub-sections as desired. Describe clearly the format of any state information you will 
        store to keep track of your movements and actions, and objects and locations of interest
        you encounter.
    </procedure>
    
    <progress>
        Record granular progress, including why you made decisions, in a list, with the current
        state last. E.g.:

        - Action: Scanned surroundings
            Reason: To understand environment and decide where to search first.

        - Action: Moved toward landmark 7.
            Reason: Living room appears beyond landmark 7. Likely to contain TV we are looking for.

        - Current state: Arrived in living room but no TV visible.
            Next steps: Scan surroundings for TV. If TV is not present, consult map to determine
            where to search next.
    </progress>
</PLAN>

Summarize all progress thus far and produce a plan for this point onwards using the above template.
"""

SUMMARIZATION_USER_PROMPT2 = """
\nHere is a plan template:

<PLAN>
    <objective>
        Explain in a few sentences the overall task objective and the condition for which it will be
        considered complete.
    </objective>

    <procedure>
        Describe the overall procedure or algorithm you will use to perform the task. List the 
        tools and capabilities that will be helpful. Use pseudo-code, lists, and write multiple
        sub-sections as desired. Describe clearly the format of any state information you will 
        store to keep track of your movements and actions, and objects and locations of interest
        you encounter.
    </procedure>
    
    <progress>
        Record granular progress, including why you made decisions, in a list, with the current
        state last. E.g.:

        - Action: Scanned surroundings
            Reason: To understand environment and decide where to search first.

        - Action: Moved toward landmark 7.
            Reason: Living room appears beyond landmark 7. Likely to contain TV we are looking for.
    </progress>

    <current_state>
        Describe the current state you are in. Provide enough context to resume.
    </current_state>

    <next_steps>
        Describe exactly what should be performed next. Be as detailed as possible so that we can
        resume from this plan without starting over.
    </next_steps>
</PLAN>

Summarize the conversation. Use the PLAN template to restate the objective and include a detailed
history of what has happened and what has been discovered so far. Most importantly, include next 
steps in sufficient detail to resume exactly where we left off without starting over. Assume nothing
apart from this new PLAN section will be retained.
"""

async def _produce_summary(messages: List[Message], model: str = "claude-sonnet-4-6") -> Message:
    # Create a shallow copy of messages
    messages = list(messages)

    # Remove all images
    messages = _remove_images_from_messages(messages=messages, keep=0)

    # If last message is an assistant message, append user message with SUMMARIZATION_USER_PROMPT.
    # Otherwise, if last message is a user message, create a deep copy of that message and append
    # the prompt to its content.
    if messages[-1].role == "assistant":
        #messages.append(Message(role="user", content=[SUMMARIZATION_USER_PROMPT]))
        messages.append(Message(role="user", content=[SUMMARIZATION_USER_PROMPT2]))
    else:
        last = messages[-1]
        #messages[-1] = Message(role=last.role, content=list(last.content) + [SUMMARIZATION_USER_PROMPT])
        messages[-1] = Message(role=last.role, content=list(last.content) + [SUMMARIZATION_USER_PROMPT2])
    # Send to LLM and return only the assistant message produced
    result = await think(
        messages=messages,
        #system=SUMMARIZATION_SYSTEM_PROMPT,
        system=SYSTEM_PROMPT,
        model=model,
    )
    return Message(role="assistant", content=[result.text])


####################################################################################################
# Helpers
####################################################################################################

# Strips all <tag>...</tag> sections (inclusive) from a message's content.
# Tags may span across multiple content items (e.g., open tag in one text item,
# images in between, close tag in another text item).
def _strip_section_from_message(message: Message, section_name: str) -> Message:
    import re
    open_tag = f"<{section_name}>"
    close_tag = f"</{section_name}>"
    new_content = []
    inside = False

    for item in message.content:
        if not isinstance(item, str):
            if not inside:
                new_content.append(item)
            continue

        result = ""
        pos = 0
        text = item

        while pos < len(text):
            if inside:
                close_idx = text.find(close_tag, pos)
                if close_idx == -1:
                    break  # rest of this text item is inside the section
                pos = close_idx + len(close_tag)
                inside = False
            else:
                open_idx = text.find(open_tag, pos)
                if open_idx == -1:
                    result += text[pos:]
                    break
                result += text[pos:open_idx]
                pos = open_idx + len(open_tag)
                inside = True

        if result:
            new_content.append(result)

    return Message(role=message.role, content=new_content)


def _content_contains(message: Message, text: str) -> bool:
    text_content = "".join([ content for content in message.content if type(content) == str ])
    return text in text_content

def _remove_all_but_last_video_frames(messages: List[Message]) -> List[Message]:
    last_video_found = False
    for i in range(len(messages) - 1, -1, -1):
        message = messages[i]
        if _content_contains(message=message, text="<video>"):
            if last_video_found:
                messages[i] = _strip_section_from_message(message=message, section_name="video")
            last_video_found = True
    return messages

def _resample(samples: List, max_samples: int) -> List:
    """Resample a list to at most max_samples, evenly distributed."""
    n = len(samples)
    if n <= max_samples:
        return samples
    indices = [round(i * (n - 1) / (max_samples - 1)) for i in range(max_samples)]
    return [samples[j] for j in indices]


class RetainMode(Enum):
    LAST_N_MESSAGES = "last_n_messages"             # count backward from the last message
    LAST_N_WITH_IMAGES = "last_n_with_images"       # count only messages that contain images


def _message_has_images(message: Message) -> bool:
    for item in message.content:
        if isinstance(item, Image):
            return True
        if isinstance(item, ToolResult):
            for c in item.content:
                if isinstance(c, Image):
                    return True
    return False


def _strip_images_from_message(message: Message) -> Message:
    new_content = []
    for item in message.content:
        if isinstance(item, Image):
            new_content.append(f"<image {item.id} removed>")
        elif isinstance(item, ToolResult):
            new_inner = []
            for c in item.content:
                if isinstance(c, Image):
                    new_inner.append(f"<image {c.id} removed>")
                else:
                    new_inner.append(c)
            new_content.append(ToolResult(tool_use_id=item.tool_use_id, content=new_inner, is_error=item.is_error))
        else:
            new_content.append(item)
    return Message(role=message.role, content=new_content)


def _remove_images_from_messages(messages: List[Message], keep: int = 2, mode: RetainMode = RetainMode.LAST_N_WITH_IMAGES) -> List[Message]:
    """Remove images from older messages, retaining them only in recent ones.

    Args:
        messages: Full message history.
        keep:     Number of messages allowed to retain images.
        mode:     LAST_N_MESSAGES counts backward from the end (regardless of
                  whether they have images). LAST_N_WITH_IMAGES counts only
                  messages that actually contain images.
    """
    # Build set of indices that are allowed to keep images
    keep_indices = set()
    if mode == RetainMode.LAST_N_MESSAGES:
        # Last N messages keep their images
        for i in range(max(0, len(messages) - keep), len(messages)):
            keep_indices.add(i)
    elif mode == RetainMode.LAST_N_WITH_IMAGES:
        # Last N messages that have images keep them
        count = 0
        for i in range(len(messages) - 1, -1, -1):
            if _message_has_images(messages[i]):
                keep_indices.add(i)
                count += 1
                if count >= keep:
                    break

    result = []
    for i, msg in enumerate(messages):
        if i in keep_indices or not _message_has_images(msg):
            result.append(msg)
        else:
            result.append(_strip_images_from_message(msg))
    return result


def _get_angle_to_image(image: Image, currentForward: VectorXZ) -> str:
    """Return a string describing the signed turn angle from the current forward direction to the
    image's camera direction. Positive = left, negative = right (matching turnInPlace convention)."""
    if image.forward is None:
        return ""
    # This math matches Unity. In Unity, positive = right but we negate the angle first there. This
    # code produces the correct result.
    dot = currentForward.x * image.forward.x + currentForward.z * image.forward.z
    cross = currentForward.x * image.forward.z - currentForward.z * image.forward.x
    angle_rad = math.atan2(cross, dot)
    angle_deg = math.degrees(angle_rad)
    return f"\nAngle from current heading -> image = {angle_deg:.0f} deg\n"


def _collect_points(images: List[Image]) -> Dict[int, VectorXZ]:
    """Collect unique points across all images, keyed by point ID."""
    points_by_id: Dict[int, VectorXZ] = {}
    for image in images:
        for point in image.points:
            points_by_id[point.id] = point.worldPosition
    return points_by_id

def _update_overhead_map(map: Optional[Map], observations_msg: ObservationsMessage) -> Tuple[Map, Image]:
    # Extract landmarks from current batch of images
    landmark_coordinates: Dict[int, VectorXZ] = {}
    for image in observations_msg.images:
        for point in image.points:
            landmark_coordinates[point.id] = point.worldPosition
    
    # No map yet? Create one.
    if map is None:
        # Compute total size of occupancy map and use that to create overhead map with coarse grid
        occupancy_map_width = observations_msg.mapCellSize * observations_msg.mapCellsWide
        occupancy_map_depth = observations_msg.mapCellSize * observations_msg.mapCellsDeep
        overhead_map_cells = 10 # per side
        overhead_map_cell_size = max(occupancy_map_width, occupancy_map_depth) / 10.0

        # Create an unexplored map
        map = Map(
            origin=VectorXZ(x=observations_msg.mapOriginX, z=observations_msg.mapOriginZ),
            cell_size=overhead_map_cell_size,
            cells_wide=overhead_map_cells,
            cells_deep=overhead_map_cells
        )

    # Robot position
    map.robot_position = observations_msg.currentPosition
    map.robot_forward = observations_msg.currentForward

    # Landmarks for this batch of images (hopefully some are in neighboring cells)
    map.landmark_coordinates = landmark_coordinates

    # Mark our position as visited
    col_and_row = map.world_to_column_and_row(x=map.robot_position.x, z=map.robot_position.z)
    if col_and_row is not None:
        col, row = col_and_row
        map.set(col=col, row=row, value="1")

    # Produce an image of the map
    pil_image = generate_images(maps=[ map ], save_to_disk=False)[0]
    data = pil_to_base64_png(image=pil_image)
    image = Image(data=data, media_type="image/png")
    
    return map, image