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
You are a robot and will be provided with a series of first-person images from different headings.
Each image is annotated with white lines marking the area of the path you would drive on the floor.
For each image, indicate whether it is safe to take the path or not. The path must not overlap any
obstacles and must encompass only unobstructed floor space. Different floor materials are acceptable
but it is important that no piece of furniture, no walls, or other tall solid objects intersect with
the proposed path.

Give your response as a list of:

    <IMAGE_NAME>: <ASSESSMENT>
"""

SYSTEM1 = SYSTEM_ROBOT
USER1 = """For each image, is it safe to drive the proposed annotated path?"""
STOP1 = []
IMAGES1 = load_images(dir="images/footprints")

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