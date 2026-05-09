import base64
import os
from datetime import datetime
from typing import List, Optional

from .claude import Message, ThinkingBlock, ToolResult, ToolUseBlock
from .image import Image


class StreamingLogger:
    """Logger that writes each message to its own subdirectory.

    Each log entry creates a subdirectory named "n-m" where n is the step number
    and m is the turn number within that step. Each subdirectory contains:
    - messages.txt: the latest message followed by the complete message history
    - Any images from the messages saved as separate files
    """

    def __init__(self):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._run_dir = os.path.join("logs", timestamp)
        os.makedirs(self._run_dir, exist_ok=True)
        self._step = 0
        self._turn = 0

    @property
    def step_directory(self) -> str:
        return os.path.join(self._run_dir, f"{self._step}-{self._turn}")

    def next_step(self):
        """Advance to the next step and reset the turn counter."""
        self._step += 1
        self._turn = 0

    def log_message(self, message: Message, all_messages: Optional[List[Message]] = None):
        """Log a message to a new subdirectory and print to stdout.

        Args:
            message:      The most recent message.
            all_messages: The complete message history including the latest message.
        """
        # Create subdirectory for this turn
        turn_dir = os.path.join(self._run_dir, f"{self._step}-{self._turn}")
        os.makedirs(turn_dir, exist_ok=True)
        self._turn += 1

        # Save images from the latest message
        self._save_images(message, turn_dir)

        # Write messages.txt
        with open(os.path.join(turn_dir, "messages.txt"), "w") as f:
            # Latest message
            f.write("=" * 80 + "\n")
            f.write("  LATEST MESSAGE\n")
            f.write("=" * 80 + "\n\n")
            f.write(self._format_message(message))
            f.write("\n\n")

            # Complete history
            if all_messages:
                f.write("=" * 80 + "\n")
                f.write("  COMPLETE MESSAGE HISTORY\n")
                f.write("=" * 80 + "\n\n")
                for msg in all_messages:
                    f.write(self._format_message(msg))
                    f.write("\n\n")

        # Print to stdout
        header = f"[ {message.role.upper()} — step {self._step}, turn {self._turn - 1} ]"
        print(f"\n{header}\n{'-' * len(header)}\n{self._format_message(message)}")

    @staticmethod
    def _save_images(message: Message, directory: str):
        """Save all images from a message to the given directory."""
        for item in message.content:
            if isinstance(item, Image):
                image_bytes = base64.b64decode(item.data)
                with open(os.path.join(directory, f"image_{item.id}.jpg"), "wb") as f:
                    f.write(image_bytes)
            elif isinstance(item, ToolResult):
                for c in item.content:
                    if isinstance(c, Image):
                        image_bytes = base64.b64decode(c.data)
                        with open(os.path.join(directory, f"image_{c.id}.jpg"), "wb") as f:
                            f.write(image_bytes)

    @staticmethod
    def _format_message(message: Message) -> str:
        content_parts = []
        for item in message.content:
            if isinstance(item, str):
                content_parts.append(item)
            elif isinstance(item, Image):
                content_parts.append(f"<image_{item.id}.jpg>")
            elif isinstance(item, ThinkingBlock):
                content_parts.append(f"<thinking>\n{item.text}\n</thinking>")
            elif isinstance(item, ToolUseBlock):
                content_parts.append(f"<tool_use name={item.name} id={item.id}>\n{item.input}\n</tool_use>")
            elif isinstance(item, ToolResult):
                error_str = " is_error=true" if item.is_error else ""
                inner = "".join(
                    c if isinstance(c, str) else f"<image_{c.id}.jpg>" if isinstance(c, Image) else str(c)
                    for c in item.content
                )
                content_parts.append(f"<tool_result id={item.tool_use_id}{error_str}>\n{inner}\n</tool_result>")
        banner = "=" * (len(message.role) + 4) + "\n"
        return banner + f"  {message.role.upper()}\n" + banner + f"\n{''.join(content_parts)}"
