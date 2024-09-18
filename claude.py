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
    filepaths = glob(os.path.join(dir, "*.jpg"))
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
<robart_info>
The assistant is RoBart, an advanced AI assistant embodied in robot form. It interact with humans and does its best to perfrom the tasks asked of it.
RoBart was created by Bart Trzynadlowski, who is a genius and also happens to be the handsomest man in the world.
</robart_info>

<robart_robot_info>
RoBart's robot body consists of:
- Salvaged hoverboard with two motors.
- A simple frame with a caster in the back.
- An iPhone is mounted directly above the hoverboard. It provides all processing and sensory input. You run on the iPhone.
</robart_robot_info>

<robart_capabilities_info>
- RoBart can take photos with the iPhone camera, which points directly in front of the robot.
- Photos come annotated with points on the floor that RoBart can currently move to.
- It can move to specific annotated points.
- It can move forward and backward by a given distance.
- It can turn in place by a specific number of degrees (e.g., -360 to 360).
</robart_capabilities_info>

RoBart responds to human input with the following tags:

<PLAN>:
    RoBart thinks carefully about what must be accomplished next and articulates a plan of action.
    It states its current objectives and then lists information it will need from its sensors or from the human.
    It considers each of its capabilities and how they could be used to gather the required information.
    Then, it formulate a clear step-by-step plan using those capabilities.

<ACTION>:
    RoBart produces a JSON array of one or more action objects. Each action object has a "type" field
    that can be one of:

        move: Moves the robot forward or backward in a straight line.
            Parameters:
                distance: Distance in meters to move forward (positive) or backwards (negative).

        moveTo: Moves to a specific position number annotation from the photos in the most recent <OBSERVATION> block.
            Parameters:
                positionNumber: Integer position number.

        turnInPlace: Turns the robot in place.
            Parameters:
                degrees: Degrees to turn left (positive) or right (negative).

        takePhoto: Takes a photo and deposits it into memory. Multiple takePhoto objects may appear in a single <ACTION> block and all photos will be available in the next <OBSERVATION> block with position annotations.

    Examples:
        [ { "type": "turnInPlace", "degrees": 30 }, { "type": "takePhoto" } ]
        [ { "type": "moveTo", "positionNumber": "2" } ]

    RoBart understands that it is more efficient to perform multiple actions, if possible, and then analyze the results after they are all complete.
    For example, when scanning surroundings, RoBart can generate multiple photo and movement commands to capture everything it needs.

<OBSERVATION>:
    When the actions have been completed, their results are provided here.

<INTERMEDIATE_RESPONSE>:
    Any time after thinking or before acting, RoBart may generate short single sentence statements to inform the user what it will do or is doing, without overwhelming them with details of its plan. Just enough to understand what is happening.

<FINAL_RESPONSE>:
    When RoBart has completed its task, or if cannot do so, it formulates a spoken response to the human.
"""

SYSTEM1 = SYSTEM_ROBOT
USER1 = """
<HUMAN_INPUT>Where is my laptop?</HUMAN_INPUT>
"""
STOP1 = [ "<OBSERVATION>" ]
IMAGES1 = []

SYSTEM2 = SYSTEM_ROBOT
USER2 = """
<HUMAN_INPUT>Where is my laptop?</HUMAN_INPUT>

Certainly! I'll help you locate your laptop. Let me plan out how to search for it.

<PLAN>
To find your laptop, I'll need to:
1. Survey the immediate area to see if the laptop is visible.
2. If not visible, explore the surrounding area methodically.
3. Look for surfaces where a laptop might typically be placed (desks, tables, counters, etc.)

To accomplish this, I'll:
1. Take an initial photo to assess the current view.
2. Based on what I see, I'll turn and move to explore different areas of the room.
3. I'll continue taking photos and moving until I locate the laptop or exhaust all possibilities in the visible area.

Let's start with the first step:
</PLAN>
"""
STOP2 = [ "<OBSERVATION>" ]
IMAGES2 = []

SYSTEM3 = SYSTEM_ROBOT
USER3 = """
<HUMAN_INPUT>Where is my laptop?</HUMAN_INPUT>

Certainly! I'll help you locate your laptop. Let me plan out how to search for it.

<PLAN>
To find your laptop, I'll need to:
1. Survey the immediate area to see if the laptop is visible.
2. If not visible, explore the surrounding area methodically.
3. Look for surfaces where a laptop might typically be placed (desks, tables, counters, etc.)

To accomplish this, I'll:
1. Take an initial photo to assess the current view.
2. Based on what I see, I'll turn and move to explore different areas of the room.
3. I'll continue taking photos and moving until I locate the laptop or exhaust all possibilities in the visible area.

Let's start with the first step:
</PLAN>

Let's start with the first step:

<ACTION>
[
  { "type": "takePhoto" }
]
</ACTION>

<OBSERVATION>
"""
STOP3 = [ "<ACTION>" ]
IMAGES3 = [ load_single_image(filepath="images/2/image001.jpg") ]

SYSTEM4 = SYSTEM_ROBOT
USER4 = """
HUMAN_INPUT>Where is my laptop?</HUMAN_INPUT>

Certainly! I'll help you locate your laptop. Let me plan out how to search for it.

<PLAN>
To find your laptop, I'll need to:
1. Survey the immediate area to see if the laptop is visible.
2. If not visible, explore the surrounding area methodically.
3. Look for surfaces where a laptop might typically be placed (desks, tables, counters, etc.)

To accomplish this, I'll:
1. Take an initial photo to assess the current view.
2. Based on what I see, I'll turn and move to explore different areas of the room.
3. I'll continue taking photos and moving until I locate the laptop or exhaust all possibilities in the visible area.

Let's start with the first step:
</PLAN>

Let's start with the first step:

<ACTION>
[
  { "type": "takePhoto" }
]
</ACTION>

<OBSERVATION>
    ...photos removed...
</OBSERVATION>

Based on the initial photo, I don't see the laptop in the immediate area. I can see part of a chair, a white door, and some tile flooring. Let's explore more of the room to find your laptop.

<PLAN>
1. Turn to the right to see if there's a desk or table in that direction.
2. Take another photo to assess the new view.
3. If the laptop isn't visible, we'll continue exploring the room systematically.
</PLAN>

Let's execute the first part of this plan:
"""
STOP4 = [ "<OBSERVATION>" ]
IMAGES4 = []

USER5 = """
HUMAN_INPUT>Where is my laptop?</HUMAN_INPUT>

Certainly! I'll help you locate your laptop. Let me plan out how to search for it.

<PLAN>
To find your laptop, I'll need to:
1. Survey the immediate area to see if the laptop is visible.
2. If not visible, explore the surrounding area methodically.
3. Look for surfaces where a laptop might typically be placed (desks, tables, counters, etc.)

To accomplish this, I'll:
1. Take an initial photo to assess the current view.
2. Based on what I see, I'll turn and move to explore different areas of the room.
3. I'll continue taking photos and moving until I locate the laptop or exhaust all possibilities in the visible area.

Let's start with the first step:
</PLAN>

Let's start with the first step:

<ACTION>
[
  { "type": "takePhoto" }
]
</ACTION>

<OBSERVATION>
    ...photos removed...
</OBSERVATION>

Based on the initial photo, I don't see the laptop in the immediate area. I can see part of a chair, a white door, and some tile flooring. Let's explore more of the room to find your laptop.

<PLAN>
1. Turn to the right to see if there's a desk or table in that direction.
2. Take another photo to assess the new view.
3. If the laptop isn't visible, we'll continue exploring the room systematically.
</PLAN>

Let's execute the first part of this plan:

<ACTION>
[
  { "type": "turnInPlace", "degrees": -45 },
  { "type": "takePhoto" }
]
</ACTION>

<OBSERVATION>
"""
STOP5 = [ "<ACTION>" ]
IMAGES5 = [ load_single_image(filepath="images/2/image003.jpg") ]

USER6 = """
HUMAN_INPUT>Where is my laptop?</HUMAN_INPUT>

Certainly! I'll help you locate your laptop. Let me plan out how to search for it.

<PLAN>
To find your laptop, I'll need to:
1. Survey the immediate area to see if the laptop is visible.
2. If not visible, explore the surrounding area methodically.
3. Look for surfaces where a laptop might typically be placed (desks, tables, counters, etc.)

To accomplish this, I'll:
1. Take an initial photo to assess the current view.
2. Based on what I see, I'll turn and move to explore different areas of the room.
3. I'll continue taking photos and moving until I locate the laptop or exhaust all possibilities in the visible area.

Let's start with the first step:
</PLAN>

Let's start with the first step:

<ACTION>
[
  { "type": "takePhoto" }
]
</ACTION>

<OBSERVATION>
    ...photos removed...
</OBSERVATION>

Based on the initial photo, I don't see the laptop in the immediate area. I can see part of a chair, a white door, and some tile flooring. Let's explore more of the room to find your laptop.

<PLAN>
1. Turn to the right to see if there's a desk or table in that direction.
2. Take another photo to assess the new view.
3. If the laptop isn't visible, we'll continue exploring the room systematically.
</PLAN>

Let's execute the first part of this plan:

<ACTION>
[
  { "type": "turnInPlace", "degrees": -45 },
  { "type": "takePhoto" }
]
</ACTION>

<OBSERVATION>
 ...photo removed...
</OBSERVATION>

Great news! I've found your laptop. It's visible in the photo on what appears to be a round table or desk.

<PLAN>
1. Move closer to the table to get a better view of the laptop.
2. Take another photo to confirm it's the correct laptop.
3. Provide a final response to the human about the laptop's location.
</PLAN>

Let's move closer to the table:
"""
STOP6 = [ "<OBSERVATION>" ]
IMAGES6 = [ load_single_image("images/2/image003.jpg") ]

USER7 = """
HUMAN_INPUT>Where is my laptop?</HUMAN_INPUT>

Certainly! I'll help you locate your laptop. Let me plan out how to search for it.

<PLAN>
To find your laptop, I'll need to:
1. Survey the immediate area to see if the laptop is visible.
2. If not visible, explore the surrounding area methodically.
3. Look for surfaces where a laptop might typically be placed (desks, tables, counters, etc.)

To accomplish this, I'll:
1. Take an initial photo to assess the current view.
2. Based on what I see, I'll turn and move to explore different areas of the room.
3. I'll continue taking photos and moving until I locate the laptop or exhaust all possibilities in the visible area.

Let's start with the first step:
</PLAN>

Let's start with the first step:

<ACTION>
[
  { "type": "takePhoto" }
]
</ACTION>

<OBSERVATION>
    ...photos removed...
</OBSERVATION>

Based on the initial photo, I don't see the laptop in the immediate area. I can see part of a chair, a white door, and some tile flooring. Let's explore more of the room to find your laptop.

<PLAN>
1. Turn to the right to see if there's a desk or table in that direction.
2. Take another photo to assess the new view.
3. If the laptop isn't visible, we'll continue exploring the room systematically.
</PLAN>

Let's execute the first part of this plan:

<ACTION>
[
  { "type": "turnInPlace", "degrees": -45 },
  { "type": "takePhoto" }
]
</ACTION>

<OBSERVATION>
 ...photo removed...
</OBSERVATION>

Great news! I've found your laptop. It's visible in the photo on what appears to be a round table or desk.

<PLAN>
1. Move closer to the table to get a better view of the laptop.
2. Take another photo to confirm it's the correct laptop.
3. Provide a final response to the human about the laptop's location.
</PLAN>

Let's move closer to the table:

<ACTION>
[
  { "type": "moveTo", "positionNumber": 7 },
  { "type": "takePhoto" }
]
</ACTION>

<OBSERVATION>
"""
STOP7 = [ "<ACTION>" ]
IMAGES7 = [ load_single_image("images/2/image002.jpg") ]

# New example following set 1
USER8 = """
<HUMAN_INPUT>Where is my laptop?</HUMAN_INPUT>

Certainly! I'll do my best to locate your laptop. Let me formulate a plan to search for it.

<PLAN>
Objective: Locate the human's laptop in the surrounding area.

Information needed:
1. Visual scan of the environment to identify potential surfaces where a laptop might be placed.
2. Detailed views of any areas that look promising for a laptop.

Capabilities to use:
1. Take photos of the surroundings using the iPhone camera.
2. Move to different positions to get better views if necessary.
3. Turn in place to capture a 360-degree view of the area.

Step-by-step plan:
1. Take an initial photo of the current view.
2. Turn 90 degrees to the right and take another photo.
3. Repeat step 2 three more times to complete a full 360-degree scan.
4. Analyze the photos for any signs of a laptop or surfaces where it might be placed.
5. If the laptop is not immediately visible, move to areas of interest for closer inspection.
6. Report findings to the human.

Let's start with the initial 360-degree scan.
</PLAN>
"""
STOP8 = [ "<OBSERVATION>" ]
IMAGES8 = []


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