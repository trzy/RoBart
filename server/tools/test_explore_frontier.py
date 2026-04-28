import argparse
import asyncio

from ..brain.image import load_image, Image
from ..brain.claude import ParamType, ToolParameter, Tool, Message, ThinkingEffort, think

SYSTEM_PROMPT = """
You are a smart AI assistant controlling a mobile, wheeled robot. You will be provided a coarse
map that tracks your exploration. Discovered landmarks are labeled as numbers. Refer to cells by
column and row (e.g., A1 is the top left cell).

You can only venture one cell in any direction. Favor familiar territory when possible.

Landmarks:
    0 = Kitchen table
    7 = Chair
    1 = Office chair

Give concise, direct answers.
"""

async def decide_next_cells(image: Image):
    print("NEXT CELL:")

    # Question
    content = [
        "We are searching for a laptop. Where do we go next?",
        image
    ]

    # Get assistant response
    response = await think(
        messages=[ Message(role="user", content=content) ],
        system=SYSTEM_PROMPT,
    )

    if response.succeeded:
        print(response.text)
    else:
        print(f"Error: Model failure: {response.text}")

    print("")

async def where_are_we(image: Image):
    print("WHERE ARE WE:")
    content = [
        "Where are we?",
        image
    ]
    response = await think(
        messages=[ Message(role="user", content=content) ],
        system=SYSTEM_PROMPT,
    )
    if response.succeeded:
        print(response.text)
    else:
        print(f"Error: Model failure: {response.text}")
    print("")

async def revisit_landmark_cells(image: Image):
    print("REVISIT LANDMARK:")
    content = [
        "Photograph the office chair. Where do we go next?",
        image
    ]
    response = await think(
        messages=[ Message(role="user", content=content) ],
        system=SYSTEM_PROMPT,
    )
    if response.succeeded:
        print(response.text)
    else:
        print(f"Error: Model failure: {response.text}")
    print("")

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("file", help="Path to an image file (JPEG or PNG)")
    args = parser.parse_args()

    data, media_type = load_image(args.file)
    image = Image(data=data, media_type=media_type, points=[])

    #await where_are_we(image=image)
    await decide_next_cells(image=image)
    await revisit_landmark_cells(image=image)

if __name__ == "__main__":
    asyncio.run(main())
    