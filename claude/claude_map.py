import asyncio
import base64
from dataclasses import dataclass
from glob import glob
import os
from typing import List

from anthropic import AsyncAnthropic

MODEL = "claude-3-5-sonnet-20240620"
client = AsyncAnthropic()

@dataclass
class Image:
    name: str
    base64_data: str
    media_type: str

def detect_media_type(image_bytes: bytes) -> str:
    if image_bytes is not None:
        if image_bytes[0:4] == b"\x89PNG":
            return "image/png"
        elif b"JFIF" in image_bytes[0:64]:  # probably should do a stricter check here
            return "image/jpeg"
        elif image_bytes[0:4] == b"RIFF" and image_bytes[8:12] == b"WEBP":
            return "image/webp"
    return "image/jpeg" # unknown, assume JPEG

def load_single_image(filepath: str) -> Image:
    with open(file=filepath, mode="rb") as fp:
        image_bytes = fp.read()
        return Image(
            name=os.path.splitext(os.path.basename(filepath))[0],
            base64_data=base64.b64encode(image_bytes).decode("utf-8"),
            media_type=detect_media_type(image_bytes=image_bytes)
        )

def load_images(dir: str) -> List[Image]:
    images = []
    filepaths = glob(os.path.join(dir, "*.jpg")) + glob(os.path.join(dir, "*.png"))
    for filepath in filepaths:
        images.append(load_single_image(filepath=filepath))
    return images

async def send(system: str, prompt: str, images: List[Image] = [], stop: List[str] = []):
    content = [ { "type": "text", "text": prompt } ]
    for image in images:
        content.append({ "type": "text", "text": f"Image: {image.name}" })
        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": image.media_type,
                "data": image.base64_data
            }
        })
    response = await client.messages.create(
        model=MODEL,
        max_tokens=1024,
        system=system,
        messages=[
            { "role": "user",  "content": content }
        ],
        stop_sequences=None if len(stop) == 0 else stop
    )
    return response.content[0].text

SYSTEM_ROBOT = """
You are a robot and will be provided with a top-down map of the area you are exploring, as mapped by
your sensors. The map contains:

- Obstructions marked blue.
- Cells you have traversed already marked in green.
- Points of interest that you have committed to memory marked as numbers.
- Your location as a red arrow. The dashed red lines are your current look direction.
- Navigable or unexplored areas are white.

Given an objective and observations from your memory, determine where to move next. You can specify movements as
- Degrees to turn left or right.
- Landmark number to move to.
"""

SYSTEM1 = SYSTEM_ROBOT
USER1 = """
<HUMAN_INPUT>Explore the area. Go to the farthest unexplored point.</HUMAN_INPUT>

<OBSERVATIONS>
Landmarks:
1: Kitchen area.
2: High countertop with stools.
3: A couch and potential entryway to another room.
4: Dining table and a tiled area.
5: A closed door.
6: Dining table with objects on it.
7: Shelves.
</OBSERVATIONS>
"""
STOP1 = []
IMAGES1 = [ load_single_image(filepath="images/maps/map1.png") ]

async def main():
    response = await send(
        system=SYSTEM_ROBOT,
        prompt=USER1,
        stop=STOP1,
        images=IMAGES1
    )
    print(response)

if __name__ == "__main__":
    asyncio.run(main())