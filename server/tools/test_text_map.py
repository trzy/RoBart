import asyncio
import traceback
from dataclasses import dataclass
from typing import List, Optional, Tuple, Dict, Any

from ..brain.image import load_image, Image, pil_to_base64_png
from ..brain.claude import ParamType, ToolParameter, Tool, Message, ThinkingEffort, think, count_tokens, context_window_size
from ..brain.streaming_logger import StreamingLogger
from ..messages import VectorXZ
from .generate_maps import Map, generate_images

class Cell:
    def __init__(self):
        # Anything the agent wants to record here
        self.memory = ""
        self.visited: bool = False

@dataclass
class Landmark:
    row: int
    col: int
    near_description: str
    far_description: str

class WorldMap:
    def __init__(self, rows: int, cols: int, robot_pos: Tuple[int, int],
                 landmarks: Optional[List[Landmark]] = None):
        self._rows = rows
        self._cols = cols
        self._robot_pos: Tuple[int, int] = robot_pos
        self._cells: List[List[Cell]] = [[Cell() for _ in range(cols)] for _ in range(rows)]
        self._landmarks: List[Landmark] = []

        if landmarks:
            for lm in landmarks:
                self.add_landmark(lm)

        occupied = {(lm.row, lm.col) for lm in self._landmarks}
        for r in range(rows):
            for c in range(cols):
                if (r, c) not in occupied:
                    self._landmarks.append(Landmark(
                        row=r, col=c,
                        near_description="empty floor space",
                        far_description="empty floor space",
                    ))

    def add_landmark(self, landmark: Landmark) -> None:
        if self.get_cell(landmark.row, landmark.col) is None:
            raise ValueError(f"Landmark at ({landmark.row},{landmark.col}) is out of bounds")
        self._landmarks.append(landmark)

    def get_cell(self, row: int, col: int) -> Cell | None:
        if 0 <= row < self._rows and 0 <= col < self._cols:
            return self._cells[row][col]
        return None

    def get_landmarks_visible(self, distance: int = 1) -> List[Landmark]:
        r0, c0 = self._robot_pos
        return [lm for lm in self._landmarks
                if abs(lm.row - r0) <= distance and abs(lm.col - c0) <= distance]

    def move_to_cell(self, row: int, col: int) -> bool:
        # success if True
        if self.get_cell(row, col) is None:
            return False
        self._robot_pos = (row, col)
        return True

    def render(self) -> str:
        row_label_w = len(str(max(self._rows - 1, 0)))
        col_label_w = len(str(max(self._cols - 1, 0)))
        cell_w = max(3, col_label_w + 2)

        left_pad = " " * (row_label_w + 1)

        header = left_pad + " " + " ".join(f"{c:^{cell_w}}" for c in range(self._cols))
        sep = left_pad + "+" + ("-" * cell_w + "+") * self._cols

        lines: List[str] = [header]
        for r in range(self._rows):
            lines.append(sep)
            row_chars = [f"{r:>{row_label_w}} |"]
            for c in range(self._cols):
                if (r, c) == self._robot_pos:
                    ch = "*"
                elif self._cells[r][c].visited:
                    ch = "x"
                else:
                    ch = " "
                row_chars.append(f"{ch:^{cell_w}}|")
            lines.append("".join(row_chars))
        lines.append(sep)
        return "\n".join(lines)



SYSTEM_PROMPT = """
You are a helpful wheeled robot that can move and inspect its surroundings. Help users with the
tasks given to you. Use the mapping tools at your disposal to keep track of your progress and make
notes about the world around you.

The world is a grid. You see it as a text map showing your position ('*'), cells you have marked
as visited ('x'), and rows/columns labeled with numbers. Cells you have not visited appear blank.
Use `scan` to detect nearby landmarks (each is reported with its row/col and an index you can pass
to `move`). Record observations in cell memory with `update_memory` and recall them later with
`recall_cells`. Use `mark_visited` to mark the current cell as visited so it shows up on the map.

Plan before acting. State your plans in <PLAN>...</PLAN> tags. Give verbal updates (of no more than
a single sentence) until you have solved the task, at which point you speak your final response.
"""

USER_PROMPT = """
Find all the plants and describe them.
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
        state last.
    </progress>

    <current_state>
        Describe the current state you are in. Include current row/col, what you have seen,
        any landmarks of interest, and any cell memory worth remembering. Provide enough context
        to resume.
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


COMPACT_TOKEN_THRESHOLD = 10000


async def _produce_summary(messages: List[Message], model: str) -> Message:
    messages = list(messages)
    if messages[-1].role == "assistant":
        messages.append(Message(role="user", content=[SUMMARIZATION_USER_PROMPT]))
    else:
        last = messages[-1]
        messages[-1] = Message(role=last.role, content=list(last.content) + [SUMMARIZATION_USER_PROMPT])
    result = await think(
        messages=messages,
        system=SYSTEM_PROMPT,
        model=model,
    )
    return Message(role="assistant", content=[result.text])


class TextMapAgent:
    def __init__(self, world: WorldMap):
        self._world = world
        self._done = False
        self._model = "claude-opus-4-7"#"claude-sonnet-4-6"

    async def _compact_history(self, messages: List[Message]) -> List[Message]:
        num_tokens = await count_tokens(messages=messages, system=SYSTEM_PROMPT, model=self._model)
        max_tokens = await context_window_size(model=self._model)
        usage_pct = 100.0 * (num_tokens / max_tokens)
        if num_tokens < COMPACT_TOKEN_THRESHOLD:
            return messages
        print(f"\nContext window usage is {usage_pct:.1f}%, compacting...\n")
        original_user_message = messages[0]
        summary_assistant_message = await _produce_summary(messages=messages, model=self._model)
        continue_user_message = Message(role="user", content=["Continue from the plan's next step"])
        return [original_user_message, summary_assistant_message, continue_user_message]

    async def _tool_view_map(self, params: Dict[str, Any]) -> List[str | Image]:
        r, c = self._world._robot_pos
        return [f"You are at row={r}, col={c}.\n{self._world.render()}"]

    async def _tool_scan(self, params: Dict[str, Any]) -> List[str | Image]:
        SCAN_DISTANCE = 2
        r0, c0 = self._world._robot_pos
        lines = [f"Scan from row={r0}, col={c0} out to {SCAN_DISTANCE} cell(s):"]
        for i, lm in enumerate(self._world._landmarks):
            d = max(abs(lm.row - r0), abs(lm.col - c0))
            if d > SCAN_DISTANCE:
                continue
            tag = "near" if d <= 1 else "far"
            desc = lm.near_description if d <= 1 else lm.far_description
            lines.append(f"  landmark {i} ({tag}) at row={lm.row}, col={lm.col}: {desc}")
        if len(lines) == 1:
            lines.append("  (no landmarks visible)")
        return ["\n".join(lines)]

    async def _tool_move(self, params: Dict[str, Any]) -> List[str | Image]:
        idx = int(params["landmark"])
        if idx < 0 or idx >= len(self._world._landmarks):
            return [f"No landmark with index {idx}."]
        lm = self._world._landmarks[idx]
        r0, c0 = self._world._robot_pos
        d = max(abs(lm.row - r0), abs(lm.col - c0))
        if d > 1:
            return [f"No path to landmark {idx} (it is {d} cells away). You can only move to a landmark in an adjacent cell. Try moving by one adjacent cell at a time."]
        if not self._world.move_to_cell(lm.row, lm.col):
            return [f"Cannot move to row={lm.row}, col={lm.col}."]
        return [f"Moved to landmark {idx} at row={lm.row}, col={lm.col}."]

    async def _tool_update_memory(self, params: Dict[str, Any]) -> List[str | Image]:
        r, c = self._world._robot_pos
        cell = self._world.get_cell(r, c)
        cell.memory = params["text"]
        return [f"Memory for row={r}, col={c} updated."]

    async def _tool_recall_cells(self, params: Dict[str, Any]) -> List[str | Image]:
        lines: List[str] = []
        for entry in params["cells"]:
            r = int(entry["row"])
            c = int(entry["col"])
            cell = self._world.get_cell(r, c)
            if cell is None:
                lines.append(f"(row={r}, col={c}): out of bounds")
                continue
            status = "visited" if cell.visited else "unvisited"
            memory = cell.memory if cell.memory else "(no memory)"
            lines.append(f"(row={r}, col={c}, {status}): {memory}")
        return ["\n".join(lines) if lines else "(no cells requested)"]

    async def _tool_mark_visited(self, params: Dict[str, Any]) -> List[str | Image]:
        r, c = self._world._robot_pos
        self._world.get_cell(r, c).visited = True
        return [f"Marked row={r}, col={c} as visited."]

    async def _tool_speak(self, params: Dict[str, Any]) -> List[str | Image]:
        print(f"RoBart says: {params['text']}")
        if params.get("final"):
            self._done = True
            print("RoBart is finished.")
            return ["RoBart is finished."]
        return ["RoBart spoke."]

    def _build_tools(self) -> List[Tool]:
        return [
            Tool(
                name="view_map",
                description="View the text map. '*' is your current position, 'x' is a cell you have marked visited, blank cells are unvisited. Row and column numbers label the axes.",
                parameters=[],
                handler=self._tool_view_map,
            ),
            Tool(
                name="scan",
                description="Scan around your current position. Returns landmarks within 2 cells of you, each with an index, row/col, and a description (more detailed when within 1 cell).",
                parameters=[],
                handler=self._tool_scan,
            ),
            Tool(
                name="move",
                description="Move to a landmark by its index (from scan). You can only move to landmarks in adjacent cells (distance 1). To reach farther landmarks, move one cell at a time.",
                parameters=[
                    ToolParameter(name="landmark", type=ParamType.INTEGER, description="Landmark index from scan results"),
                ],
                handler=self._tool_move,
                rewrite_history=self._compact_history,
            ),
            Tool(
                name="update_memory",
                description="Set a description/note for the current cell. Overwrites any prior memory for this cell.",
                parameters=[
                    ToolParameter(name="text", type=ParamType.STRING, description="Note to store for the current cell"),
                ],
                handler=self._tool_update_memory,
            ),
            Tool(
                name="recall_cells",
                description="Given a list of cell coordinates, return their visited status and any stored memory.",
                parameters=[
                    ToolParameter(
                        name="cells",
                        type=ParamType.ARRAY,
                        description="Cells to recall",
                        required=True,
                        properties=[
                            ToolParameter(name="row", type=ParamType.INTEGER, description="Row index"),
                            ToolParameter(name="col", type=ParamType.INTEGER, description="Column index"),
                        ],
                        array_type=ParamType.OBJECT,
                    ),
                ],
                handler=self._tool_recall_cells,
            ),
            Tool(
                name="mark_visited",
                description="Mark the current cell as visited. Use this to track where you have been, or to ascribe any other meaning to a cell.",
                parameters=[],
                handler=self._tool_mark_visited,
            ),
            Tool(
                name="speak",
                description="Speak out loud. Use this to inform nearby people of what you are about to do and to deliver final responses. Be direct and concise because this will be spoken.",
                parameters=[
                    ToolParameter(name="text", type=ParamType.STRING, description="Text to speak"),
                    ToolParameter(name="final", type=ParamType.BOOLEAN, description="If true, we are finished and speaking our final response"),
                ],
                handler=self._tool_speak,
            ),
        ]

    async def run(self, instructions: str, model: str = "claude-sonnet-4-6"):
        print(f"Using model: {model}")
        self._model = model
        tools = self._build_tools()
        logger = StreamingLogger()
        messages = [Message(role="user", content=[f"<HUMAN_INPUT>{instructions}</HUMAN_INPUT>"])]

        try:
            while not self._done:
                logger.next_step()
                for msg in messages:
                    logger.log_message(msg, all_messages=messages)

                response = await think(
                    messages=messages,
                    system=SYSTEM_PROMPT,
                    model=model,
                    thinking=ThinkingEffort.NONE,
                    tools=tools,
                    on_message=logger.log_message,
                )

                if not response.succeeded:
                    print(f"Error: Model failure: {response.text}")
                    return

                messages.extend(response.messages)
        except Exception as e:
            print(f"Error: Exception caught: {e}")
            traceback.print_exc()


async def main():
    world = WorldMap(
        rows=10,
        cols=10,
        robot_pos=(1, 5),
        landmarks=[
            Landmark(row=2, col=4, near_description="a red mug on a desk",
                     far_description="a small red object on a desk"),
            Landmark(row=2, col=4, near_description="a stack of books beside the mug",
                     far_description="a dark rectangular shape near the red object"),
            Landmark(row=9, col=9, near_description="a potted plant in the corner",
                     far_description="green foliage in the far corner"),
            Landmark(row=0, col=9, near_description="a window with daylight",
                     far_description="a bright rectangle on the wall"),
            Landmark(row=7, col=3, near_description="two potted flowers on a table",
                     far_description="a table"),
            Landmark(row=3, col=8, near_description="a shelf with a small succulent and some photographs",
                     far_description="a tall shelf")
        ],
    )

    print("Initial map:")
    print(world.render())
    print()

    agent = TextMapAgent(world=world)
    await agent.run(instructions=USER_PROMPT.strip())

    print()
    print("Final map:")
    print(world.render())


if __name__ == "__main__":
    asyncio.run(main())
