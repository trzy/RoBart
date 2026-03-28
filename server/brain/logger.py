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
#   output.txt       — model response for this step
#   image_N.jpg ...  — every image referenced in this step's input (may repeat across steps)
####################################################################################################

class BrainLogger:
    def __init__(self):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._run_dir = os.path.join("logs", timestamp)
        os.makedirs(self._run_dir, exist_ok=True)
        self._step = 0
        self._step_dir: Optional[str] = None

    def log_input(self, messages: List[Message]):
        """Call before think(). Creates the step directory, saves images, and writes input.txt."""
        self._step_dir = os.path.join(self._run_dir, str(self._step))
        os.makedirs(self._step_dir, exist_ok=True)

        for msg in messages:
            for item in msg.content:
                if isinstance(item, Image):
                    image_bytes = base64.b64decode(item.data)
                    with open(os.path.join(self._step_dir, f"image_{item.id}.jpg"), "wb") as f:
                        f.write(image_bytes)

        formatted = self._format_messages(messages)
        with open(os.path.join(self._step_dir, "input.txt"), "w") as f:
            f.write(formatted)
        self._print_section("INPUT", self._step, formatted)

    def log_output(self, response: str):
        """Call immediately after think(). Writes output.txt to the current step directory."""
        with open(os.path.join(self._step_dir, "output.txt"), "w") as f:
            f.write(response)
        self._print_section("OUTPUT", self._step, response)
        self._step += 1

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
