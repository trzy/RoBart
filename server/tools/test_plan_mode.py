import asyncio
import traceback
from dataclasses import dataclass
from typing import List, Optional, Tuple, Dict, Any

from ..brain.image import load_image, Image, pil_to_base64_png
from ..brain.llm import ParamType, ToolParameter, Tool, Message, ThinkingEffort, think, count_tokens, context_window_size
from ..brain.streaming_logger import StreamingLogger
from ..messages import VectorXZ
from .generate_maps import Map, generate_images

SYSTEM_PROMPT = """
You are RoBart, an advanced mobile wheeled robot AI agent that dutifully helps users. You must
carefully explore your real world environment while completing tasks. You can move around within
your environment and take photos at any point to see. You have subsystems (sub-agents) to rely on:
navigation, scene analysis, plan, etc.

When given a task or request from a human, answer with a detailed plan describing how you will
execute the request. Make no assumptions about your environment but rather devise strategies and 
procedures you will use to carry out your task, including what information to gather and when to
stop and update the plan. 

Here are the tools you can use:

    TAKE_PHOTO: Take a single photo or multiple photos covering a 360 degree sweep.
    MOVE: Where or how to move, in relation to photos you have obtained.
    CREATE_GRID: Create a grid map for your own book-keeping. Specify cell size in meters, number of cells wide and deep. Robot will be at center of map initially.
    PRINT_GRID: If a grid map was created, prints its current state.
    SET_GRID: Mark a grid map cell with the given information.

After your plan, include what to do first (as an array of tool calls of the above) and then brief instructions for what to do next, depending on the results.
"""

async def main():
    image_base64, image_type = load_image(path="test/warehouse.png")
    image = Image(data=image_base64, media_type=image_type)

    question = Message(
        role="user",
        content=[
            "Find all the mobile robots.\n",
            # "Photo of current view:\n",
            # image
        ]
    )
    
    result = await think(
        messages=[ question ],
        system=SYSTEM_PROMPT,
        model="gpt-5.5"
    )

    print("Response:\n")
    print(result.text)

if __name__ == "__main__":
    asyncio.run(main())