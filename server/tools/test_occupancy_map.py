#
# Idea:
#
# High-level navigation "mode" that is occasionally invoked to set a sub-task instructing robot to
# focus on a particular region. In this example, we load an occupancy map with landmarks as well as
# green, traversed cells rendered. 
#

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
You are RoBart, an advanced mobile wheeled robot AI agent that dutifully helps users. You can move
and turn freely but can also detect navigable points on the ground and use them as references for
both movement and direction. These are identified with unique numbers.

<occupancy_maps>
Occupancy maps are rendered on a grid. Cells are blue if obstructed otherwise may be either unobstructed
floor or simply unexplored. Green cells are cells that RoBart has traversed already. Landmark points
are rendered as numbers.
</occupancy_maps>
"""

async def main():
    image_base64, image_type = load_image(path="occupancy_map_test.png")
    image = Image(data=image_base64, media_type=image_type)

    question = Message(
        role="user",
        content=[
            image,
            "We are searching for mobile robots but have not found any yet. Where should we head next?"
        ]
    )
    
    result = await think(
        messages=[ question ],
        system=SYSTEM_PROMPT
    )

    print("Response:\n")
    print(result.text)

if __name__ == "__main__":
    asyncio.run(main())