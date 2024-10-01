import asyncio
import base64
from dataclasses import dataclass
from glob import glob
from io import BytesIO
import json
import os
from typing import List

from anthropic import AsyncAnthropic

from PIL import Image as PILImage, ImageDraw
import matplotlib.pyplot as plt

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

def display_annotated_image(json_data: str, image_base64: str):
    image_data = base64.b64decode(image_base64)
    image = PILImage.open(BytesIO(image_data))
    width, height = image.size
    objs = json.loads(json_data)
    draw = ImageDraw.Draw(image)
    dot_radius = 10
    for item in objs:
        x = item['x']
        y = height - item['y']  # stupid matplotlib has inverted y (0 is bottom)

        x = width * item['nx']
        y = height * (1.0 - item['ny'])  # stupid matplotlib has inverted y (0 is bottom)

        label = item['query']
        draw.ellipse((x-dot_radius, y-dot_radius, x+dot_radius, y+dot_radius), fill='red')
        draw.text((x + dot_radius + 5, y - dot_radius), label, fill='white')
    plt.figure(figsize=(8, 8))
    plt.imshow(image)
    plt.axis('off')  # Hide the axis
    plt.show()

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
You are a robot and will be provided with a first-person image. Return the pixel coordinates of
objects and locations, as well as the normalized coordinates (between 0 and 1 on each axis) of queries in JSON format.
(0,0) should be the top-left coordinate, with increasing y going down. E.g.:
[
    { "query": "chair", "x": 100, y: "576", "nx": "0.2", "ny": "0.45" },
    { "query": "lamp", "x": 787, y: "1023", "nx": "0.8", "ny": "0.9" }
]

The output must be only JSON, no other text or the parser will fail!
"""

SYSTEM1 = SYSTEM_ROBOT
USER1 = """Precisely locate the red square, the purple socks, laptop, and the nearest chair. Give the locations as positions on the floor nearest all objects."""
STOP1 = []
IMAGES1 = [ load_single_image(filepath="images/1/image003.jpg") ]

async def main():
    response = await send(
        system=SYSTEM_ROBOT,
        prompt=USER1,
        stop=STOP1,
        images=IMAGES1
    )
    print(response)
    display_annotated_image(json_data=response, image_base64=IMAGES1[0].base64_data)

if __name__ == "__main__":
    asyncio.run(main())