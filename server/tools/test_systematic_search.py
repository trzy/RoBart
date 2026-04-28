# Explore entire map

import argparse
import asyncio
from typing import List, Tuple, Dict, Any

from ..brain.image import load_image, Image, pil_to_base64_png
from ..brain.claude import ParamType, ToolParameter, Tool, Message, ThinkingEffort, think
from ..brain.streaming_logger import StreamingLogger
from .generate_maps import Map, generate_images

SYSTEM_PROMPT = """
You are a smart AI assistant controlling a mobile, wheeled robot. You will be provided a coarse
map that tracks your exploration. Discovered landmarks are labeled as numbers. Refer to cells by
column and row (e.g., A1 is the top left cell).

You can only venture one cell in any direction. Favor familiar territory when possible.
"""

def update_cell(cells: List[str], yi: int, xi: int, char: str):
    assert len(char) == 1
    row = cells[yi]
    row = row[:xi] + char + row[xi+1:]
    cells[yi] = row

def get_current_coord(map: Map) -> Tuple[str | None, int, int]:
    cells = map.map
    num_rows = len(cells)
    num_cols = len(cells[0])
    for yi in range(num_rows):
        for xi in range(num_cols):
            coord_letter = chr(ord("a") + xi)
            coord_number = yi + 1   # starts with 1
            if cells[yi][xi] == "x":
                return f"{coord_letter}{coord_number}", yi, xi
    return None, 0, 0
    
def update_map(map: Map, to: str) -> str:
    to = to.lower()

    # Map size
    cells = map.map
    num_rows = len(cells)
    num_cols = len(cells[0])

    # Decode and validate "to" position
    to_yi = int(to[1]) - 1          # y is the number [1,num_rows]
    to_xi = ord(to[0]) - ord("a")   # x is the letter
    if to_yi < 0 or to_yi >= num_rows or to_xi < 0 or to_xi >= num_cols:
        return f"Destination coordinate {to} is out of bounds (y={to_yi}, x={to_xi}) of map"

    # Find existing position
    coord, yi, xi = get_current_coord(map=map)
    if coord is None:
        return "Cannot find robot on map"
    
    # Coordinate: (yi,xi)
    # Check bounds
    if yi >= num_rows or yi < 0 or xi >= num_cols or xi < 0:
        # Error: cannot move (bounds)
        return "Cannot move beyond map bounds"
    
    # Move!
    update_cell(cells=cells, yi=yi, xi=xi, char="1")        # mark old position as visited
    update_cell(cells=cells, yi=to_yi, xi=to_xi, char="x")  # move robot
    
    # Successful
    return f"Moved from {coord} to {to}"

def map_to_image(map: Map) -> Image:
    pil_image = generate_images(maps=[ map ], save_to_disk=False)[0]
    data = pil_to_base64_png(image=pil_image)
    return Image(data=data, media_type="image/png")

async def main():
    map = Map(
        map=[
            "000000",
            "000000",
            "000x00",
            "000000",
        ],
        landmarks_by_cell={}
    )

    async def handle_move_tool(params: Dict[str, Any]) -> List[str | Image]:
        result = update_map(map=map, to=params["coordinate"])
        print(map)
        return [ result, "\nNew map:\n", map_to_image(map=map) ]

    logger = StreamingLogger()

    messages = [
        Message(
            role="user",
            content=[
                "Explore the entire map.",
                map_to_image(map=map)
            ]
        )
    ]

    logger.next_step()
    for msg in messages:
        logger.log_message(msg)

    response = await think(
        messages=messages,
        system=SYSTEM_PROMPT,
        tools=[
            Tool(
                name="move",
                description="Move to a neighboring cell.",
                parameters=[
                    ToolParameter(name="coordinate", type=ParamType.STRING, description="Coordinate (column and row) to move to, e.g. b5 "),
                ],
                handler=handle_move_tool,
            ),
        ],
        on_message=logger.log_message,
    )

    # coord = get_current_coord(map=map)
    # print(f"Starting coordinate: {coord}")
    # print(map)
    # path = [ "e3", "f3", "f2", "e1", "d1", "c1", "b1", "a1" ]

    # for next_coord in path:
    #     print(f"Move to: {next_coord}")
    #     result = update_map(map=map, to=next_coord)
    #     print(result)
    #     print(map)

if __name__ == "__main__":
    asyncio.run(main())