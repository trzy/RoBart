import base64
from openai import OpenAI

from .system_prompt import SYSTEM_PROMPT


def load_image_as_data_url(path: str) -> str:
    """
    Load an image from disk and return a data URL suitable for input_image.
    """
    with open(path, "rb") as f:
        encoded = base64.b64encode(f.read()).decode("utf-8")
    return f"data:image/jpeg;base64,{encoded}"

INPUT = """
<HUMAN_INPUT>Find the avocados</HUMAN_INPUT>
<PLAN>
    - Long-term plan of action
        Find the avocado display in the produce section, move close enough to confirm visually or via signage, and report/stop there.
    - Check current observations to determine if the long-term task complete
        Not complete; I cannot yet confirm avocados from this single forward view without annotated navigable points.
    - Current sub-problem RoBart is working on
        Get annotated photos of the surrounding produce area to locate avocados or signs pointing to them.
    - How is the recent progress? Is headway being made or does planning need adjustment?
        Just starting; need a fresh annotated photo before choosing a safe point to approach.
    - What information is needed to achieve the current sub-problem and the longer-term plan?
        - A clear photo with navigable points of the produce islands ahead.
        - Visual confirmation of avocados (dark green, pear-shaped fruit) or “Avocados” signage.
    - What capabilities can be used?
        takePhoto to get an annotated view; then moveTo or small forward move if a safe point near the produce island is available; scan360 if needed.
    - A step by step plan of action for the immediate next steps
        1) Take a photo straight ahead to obtain navigable points and inspect produce bins for avocados/signage.
        2) If avocados are visible and a safe point is annotated near them, moveTo that point; otherwise, perform a 360 scan to search wider and select a safe approach point.
</PLAN>

<MEMORY>
    []
</MEMORY>

<INTERMEDIATE_RESPONSE>
    I’m going to take a photo of the produce section ahead to spot the avocados.
</INTERMEDIATE_RESPONSE>

<ACTIONS>
    [
        { "type": "takePhoto" }
    ]
</ACTIONS>
""" + \
"""
<OBSERVATIONS>
A person is blocking your path.
</OBSERVATIONS>
"""

if __name__ == "__main__":
    client = OpenAI()  # uses OPENAI_API_KEY from environment

    image_data_url = load_image_as_data_url("docs/Readme/Images/grocery_cover.jpg")

    response = client.responses.create(
        model="gpt-5",
        input=[
            {
                "role": "system",
                "content": [
                    {
                        "type": "input_text",
                        "text": SYSTEM_PROMPT
                    }
                ]
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": INPUT
                    },
                    {
                        "type": "input_image",
                        "image_url": image_data_url
                    },
                    # {
                    #     "type": "input_text",
                    #     "text": "Goodbye"
                    # }
                ]
            }
        ]
    )

    print(response.output_text)
