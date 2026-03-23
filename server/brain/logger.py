import base64
import os
from datetime import datetime
from typing import List, Optional

from .claude import Message
from .image import Image


####################################################################################################
# BrainLogger
#
# Writes one directory per run (logs/<timestamp>/) with a numbered subdirectory per step.
# Each step directory contains:
#   input.txt        — formatted message history fed into the model this step
#   output.txt       — model response from the previous step (absent for step 0)
#   image_N.jpg ...  — every image referenced in this step (may repeat across steps)
####################################################################################################

class BrainLogger:
    def __init__(self):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._run_dir = os.path.join("logs", timestamp)
        os.makedirs(self._run_dir, exist_ok=True)
        self._step = 0

    def log_step(self, messages: List[Message], prev_response: Optional[str]):
        step = self._step
        step_dir = os.path.join(self._run_dir, str(step))
        os.makedirs(step_dir, exist_ok=True)
        self._step += 1

        # Save all images referenced in this step's message history
        for msg in messages:
            for item in msg.content:
                if isinstance(item, Image):
                    image_bytes = base64.b64decode(item.data)
                    with open(os.path.join(step_dir, f"image_{item.id}.jpg"), "wb") as f:
                        f.write(image_bytes)

        # output.txt — model response from previous step
        if prev_response is not None:
            with open(os.path.join(step_dir, "output.txt"), "w") as f:
                f.write(prev_response)
            self._print_section("OUTPUT", step - 1, prev_response)

        # input.txt — full message history going into this step (absent for the final output-only step)
        if messages:
            formatted = self._format_messages(messages)
            with open(os.path.join(step_dir, "input.txt"), "w") as f:
                f.write(formatted)
            self._print_section("INPUT", step, formatted)

    @staticmethod
    def _print_section(kind: str, step: int, content: str):
        header = f"[ {kind} — step {step} ]"
        print(f"\n{header}\n{'-' * len(header)}\n{content}")

    def _format_messages(self, messages: List[Message]) -> str:
        parts = []
        for msg in messages:
            content_parts = []
            for item in msg.content:
                if isinstance(item, str):
                    content_parts.append(item)
                elif isinstance(item, Image):
                    content_parts.append(f"<image_{item.id}.jpg>")
            banner = "=" * (len(msg.role) + 4) + "\n"
            parts.append(banner + f"  {msg.role.upper()}\n" + banner + f"\n{''.join(content_parts)}")
        return "\n\n".join(parts)
