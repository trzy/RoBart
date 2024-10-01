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
You are a robot and will be provided with a first-person image annotated with equidistant curves
indicating distances from your current position and dashed lines indicating angles. You are at 0 degrees
and the given angles are relative to that.

Use these guides to determine precisely how much to turn and then how far to move forward to reach
an objective. Give a precise angle and distance, interpolating between curves and lines as needed.

Format outputs for each item or location as JSON. E.g.:

[
    { "query": "chair", "angle": -13, "distance": 0.75 },
    { "query": "lamp", "angle": 48, "distance": 3.1 }
]
"""

SYSTEM1 = SYSTEM_ROBOT
USER1 = """Precisely locate the red square, the purple socks, laptop, and the nearest chair."""
STOP1 = []
IMAGES1 = [ load_single_image(filepath="images/geometric_guides/geometric_guides1.png") ]

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