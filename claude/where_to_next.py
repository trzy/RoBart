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

def load_images(dir: str) -> List[Image]:
    images = []
    filepaths = glob(os.path.join(dir, "*.jpg"))
    for filepath in filepaths:
        with open(file=filepath, mode="rb") as fp:
            image_bytes = fp.read()
            image = Image(
                name=os.path.splitext(os.path.basename(filepath))[0],
                base64_data=base64.b64encode(image_bytes).decode("utf-8"),
                media_type=detect_media_type(image_bytes=image_bytes)
            )
            images.append(image)
    return images

async def send(system: str, prompt: str, images: List[Image] = []):
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
        ]
    )
    return response.content[0].text

async def main():
    response = await send(
        system="You are a robot consisting of two-wheeled motorized base and an iPhone that controls it, rigidly mounted above the wheels. Images come from the iPhone camera. Follow instructions from the user and use your sensory inputs to formulate your responses. Respond to everything ask but be brief and concise.",
        prompt="Images of your surroundings are provided with numbered labels of reachable positions on the floor. The time is 3:00PM. Where would you go to find your master's laptop? Give a position number.",
        images=load_images(dir="images/2")
    )
    print(response)

if __name__ == "__main__":
    asyncio.run(main())