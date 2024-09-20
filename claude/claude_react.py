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

async def main():

    SYSTEM_ROBOT = """
    You are the world's most advanced smart assistant embodied in a robot named RoBart. Do your best to be helpful and utilize your robot body as best you can to do what you are told.

    DESCRIPTION OF YOUR ROBOT BODY AND ITS CAPABILITIES:
    You are built from a repurposed hoverboard, a simple chassis made of aluminum extrusions, a third caster wheel in the rear, and an iPhone rigidly mounted above the hoverboard.
    Here are your capabilities:
        - Take photos: Photos can be acquired from the iPhone camera and will come labeled with integer numbers (0, 1, 2, ...) representing points on the floor that you can move to.
        - Move: You can drive forward and backwards by a specified amount or to a floor point labeled in a photo (e.g., "move to point 9 in photo image000")
        - Sample current position: Your position is tracked in 3D space and you can always get the current world position, orientation (including as forward, up, and right vectors), or entire transform matrix.
        - Turn in place; You can turn in place by an arbitrary number of degrees ranging from [-360,+360].
        - Speak: You can speak to the user.

    FORMAT OF YOUR RESPONSES:
    Your responses must follow this format:

    Human Input: What was said to you by a human -- the question you must answer, command you must obey, task you must perform, or statement that you must respond to.
    Thought: You must think about what to do and plan a detailed course of action for the robot. The plan should make clear use of robot capabilities as well as previous observations. Present trade-offs and implementation choices. Consider capabilities available to you.
    Action:
    {CODE}
    Observation: The result of the action: photo buffer and console output.
    ... repeat Thought/Action/Observation as many times as required to arrive at a final response ...
    Thought: I am now able to give a final response.
    Final Response: Your final verbal response to the human. Be as concise as possible.
    """


    SYSTEM_PROGRAMMER = """
    You are an expert in writing software in JavaScript that runs in JavaScriptCore on a robot. You are given a dialog between a human and a robot, as well as the robot's
    planning and thought process. Write high quality code to accomplish what the robot wants to do, checking for and recovering from errors if possible along the way.

    CODE GUIDELINES:
    Write straightforward JavaScript. This code will be executed on the iPhone in a JavaScriptCore environment. Therefore, no functions outside of core language functions are available.
    The code will not run in a web browser.

    API:
    Here are the functions and data structures made available in the JavaScriptCore environment for you to use:

        print(message):
            Prints a message to the console. After each code block execution, the console messages will be provided to the robot.
            These can be used to return information about program execution state and other observations.
            Returns: void
        clearPhotoBuffer()
            Returns: void
            Clears the photo buffer of all images.
        takeOnePhoto()
            Returns: void
            Takes one photo and deposits it in the photo buffer (which the robot will be able to inspect after all code finished).
        scan360()
            This function will rotate the robot 360 degrees and snap a series of photos that are appended to the photo buffer.
            Returns: void
        moveTo(positionNumber)
            This function will attempt to move the robot to a position. It may not succeed.
            Inputs:
                positionNumber: An integer corresponding to one of the labeled points in the images of the current photo buffer.
            Returns: bool
                True if the robot was able to move to the location, false otherwise. Use this to determine if the robot actually moved to the desired location.
        speak(message)
            Speaks to the user.
            Inputs:
                message: A string to speak.
            Returns: void

    OUTPUT ONLY VALID JAVASCRIPT CODE THAT CAN BE EXECUTED IN JAVASCRIPTCORE. DO NOT PROVIDE ANY OTHER OUTPUT.
    """

    SYSTEM1 = SYSTEM_ROBOT
    USER1 = f"""
    Human Input: Where is my laptop?
    """
    STOP1 = [ "Action:" ]
    IMAGES1 = []

    SYSTEM2 = SYSTEM_PROGRAMMER
    USER2 = f"""
    Human Input: Where is my laptop?

    Thought: To find the laptop, I'll need to survey the area using my camera and movement capabilities. I'll start by taking a photo of my current surroundings, then plan my next steps based on what I see.
    """
    STOP2 = []
    IMAGES2 = []

    SYSTEM3 = SYSTEM_PROGRAMMER
    USER3 = f"""
    Human Input: Where is my laptop?

    Thought: To find the laptop, I'll need to survey the area using my camera and movement capabilities. I'll start by taking a photo of my current surroundings, then plan my next steps based on what I see.

    Action:
    Here's the JavaScript code to start the search for the laptop:

    ```javascript
    // Clear any existing photos in the buffer
    clearPhotoBuffer();

    // Take a photo of the current surroundings
    takeOnePhoto();

    // Print a message to indicate the initial photo has been taken
    print("Initial photo taken. Analyzing surroundings.");

    // Perform a 360-degree scan to get a complete view of the area
    scan360();

    print("360-degree scan completed. Photos are now in the buffer for analysis.");

    // Speak to the user to provide an update
    speak("I've taken photos of the surrounding area. I'll analyze them to look for your laptop.");

    // Note: The actual analysis of the photos will be done by the robot's vision system outside of this code.
    // The results of that analysis will determine the next steps, which may involve moving to different locations.

    print("Ready for further instructions based on photo analysis.");
    ```

    This code accomplishes the following:

    1. Clears any existing photos from the buffer to ensure we're working with fresh data.
    2. Takes an initial photo of the current surroundings.
    3. Performs a 360-degree scan to get a comprehensive view of the area.
    4. Provides feedback through print statements and speaks to the user to inform them of the progress.

    The next steps would involve analyzing the photos (which is done outside this code) and then potentially moving to different locations based on that analysis. Once we have more information from the photo analysis, we can write additional code to move the robot and continue the search.

    Observation:
    ```console log
    Initial photo taken. Analyzing surroundings.
    360-degree scan completed. Photos are now in the buffer for analysis.
    Ready for further instructions based on photo analysis.
    ```

    Thought: After analyzing the photos from the 360-degree scan, I don't see the laptop in the immediate area. However, I can see that we're in what appears to be a kitchen or dining area with tile flooring, white cabinets, and a staircase leading to an upper level. The laptop might be in another room or on a higher floor. I'll need to explore further to locate it.
    """
    STOP3 = [ ]
    IMAGES3 = []#load_images(dir="images/2")

    response = await send(
        system=SYSTEM3,
        prompt=USER3,
        stop=STOP3,
        images=IMAGES3
    )
    print(response)

if __name__ == "__main__":
    asyncio.run(main())