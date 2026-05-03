# Explore entire map

import argparse
import asyncio
from typing import List, Optional, Tuple, Dict, Any

from ..brain.image import load_image, Image, pil_to_base64_png
from ..brain.claude import ParamType, ToolParameter, Tool, Message, ThinkingEffort, think
from ..brain.streaming_logger import StreamingLogger
from ..messages import VectorXZ
from .generate_maps import Map, generate_images

SYSTEM_PROMPT = """
You are a smart AI assistant controlling a mobile, wheeled robot. You will be provided a coarse
map that tracks your exploration. Discovered landmarks are labeled as numbers. Refer to cells by
column and row (e.g., A1 is the top left cell).

You can only venture one cell in any direction. Favor familiar territory when possible.
"""

def get_current_coord(map: Map) -> Optional[str]:
    return map.world_to_cell(map.robot_position.x, map.robot_position.z)

def update_map(map: Map, to: str) -> str:
    to = to.lower()

    # Decode and validate "to" position
    to_xi, to_yi = Map._parse_cell_key(to)
    if to_yi < 0 or to_yi >= map.cells_deep or to_xi < 0 or to_xi >= map.cells_wide:
        return f"Destination coordinate {to} is out of bounds (y={to_yi}, x={to_xi}) of map"

    from_coord = get_current_coord(map=map)

    # Move robot to center of target cell, mark it visited
    map.robot_position = VectorXZ(x=map.origin.x + (to_xi + 0.5) * map.cell_size,
                                  z=map.origin.z + (to_yi + 0.5) * map.cell_size)
    map.map[to_yi][to_xi] = "1"

    return f"Moved from {from_coord} to {to}"

def map_to_image(map: Map) -> Image:
    pil_image = generate_images(maps=[ map ], save_to_disk=False)[0]
    data = pil_to_base64_png(image=pil_image)
    return Image(data=data, media_type="image/png")

async def main():
    map = Map.from_strings(
        rows=[
            "000000",
            "000000",
            "000x00",
            "000000",
        ],
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