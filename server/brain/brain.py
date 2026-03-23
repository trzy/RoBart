import asyncio
import json
from typing import Awaitable, Callable, Optional

from pydantic import BaseModel

from .claude import Message, think
from .block_parser import parse_blocks
from .image import decode_annotated_image
from .logger import BrainLogger
from .prompts import SYSTEM_PROMPT
from ..messages import ActionsMessage, ObservationsMessage

STOP_TAG = "<OBSERVATIONS>"


####################################################################################################
# Brain
#
# Drives the AI loop: submits instructions to Claude, dispatches actions to the robot, and waits
# for observations before continuing.
####################################################################################################

class Brain:
    def __init__(self):
        self._send: Optional[Callable[[BaseModel], Awaitable[None]]] = None
        self._observations_queue: asyncio.Queue[ObservationsMessage] = asyncio.Queue()

    def set_send(self, send: Callable[[BaseModel], Awaitable[None]]):
        self._send = send

    async def on_observations_message(self, session, msg: ObservationsMessage, timestamp: float):
        await self._observations_queue.put(msg)

    async def run(self, instructions: str, model: str = "claude-sonnet-4-6"):
        try:
            logger = BrainLogger()
            messages = [Message(role="user", content=[f"<HUMAN_INPUT>{instructions}</HUMAN_INPUT>"])]
            prev_response = None
            while True:
                logger.log_step(messages, prev_response)

                response = await think(
                    messages=messages,
                    system=SYSTEM_PROMPT,
                    model=model,
                    stop_sequences=[STOP_TAG],
                )
                blocks = parse_blocks(response)
                tags = [b.tag for b in blocks]

                messages.append(Message(role="assistant", content=[response]))
                prev_response = response

                if "FINAL_RESPONSE" in tags:
                    logger.log_step([], prev_response)
                    break

                actions = _extract_actions(blocks)
                if actions and self._send:
                    await _send_actions(self._send, actions)
                    obs_msg = await _wait_for_observations(self._observations_queue)
                else:
                    obs_msg = None

                obs_content = _format_observations(obs_msg)
                messages.append(Message(role="user", content=obs_content))
        except Exception as e:
            print(f"Error: Exception caught: {e}")


####################################################################################################
# Helpers
####################################################################################################

def _extract_actions(blocks) -> list[str]:
    for b in blocks:
        if b.tag == "ACTIONS":
            try:
                action_list = json.loads(b.content.strip())
                return [json.dumps(action) for action in action_list]
            except (json.JSONDecodeError, TypeError) as e:
                print(f"Warning: failed to parse ACTIONS JSON: {e}")
                return []
    return []

async def _send_actions(send, actions: list[str]):
    await send(ActionsMessage(actions=actions))

async def _wait_for_observations(queue: asyncio.Queue) -> ObservationsMessage:
    return await queue.get()

def _format_observations(msg: Optional[ObservationsMessage]) -> list:
    if msg is None:
        return ["<OBSERVATIONS>\nStep completed successfully.\n</OBSERVATIONS>"]
    if not msg.images:
        return [f"<OBSERVATIONS>\n{msg.description}\n</OBSERVATIONS>"]
    label = "Image:" if len(msg.images) == 1 else "Images:"
    content = [f"<OBSERVATIONS>\n{msg.description}\n{label}\n"]
    for annotated_image in msg.images:
        content.append(decode_annotated_image(annotated_image))
    content.append("</OBSERVATIONS>")
    return content
