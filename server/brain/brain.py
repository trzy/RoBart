from .claude import Image, Message, think
from .block_parser import parse_blocks
from .prompts import SYSTEM_PROMPT

STOP_TAG = "<OBSERVATIONS>"


async def run_brain(instructions: str, model: str = "claude-sonnet-4-6"):
    messages = [Message(role="user", content=[f"<HUMAN_INPUT>{instructions}</HUMAN_INPUT>"])]

    while True:
        response = await think(
            messages=messages,
            system=SYSTEM_PROMPT,
            model=model,
            stop_sequences=[STOP_TAG],
        )

        # Print full response and which tags were found
        print(f"\n{response}")
        blocks = parse_blocks(response)
        tags = [b.tag for b in blocks]
        print(f"[Tags: {', '.join(tags) if tags else '(none)'}]")

        # Append assistant turn
        messages.append(Message(role="assistant", content=[response]))

        # Stop if final response reached
        if "FINAL_RESPONSE" in tags:
            break

        # Inject placeholder observations as next user turn
        observations = "<OBSERVATIONS>\nStep completed successfully.\n</OBSERVATIONS>"
        messages.append(Message(role="user", content=[observations]))
