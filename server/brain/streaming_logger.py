import base64
import os
from datetime import datetime
from typing import Optional

from .claude import Message, ToolResult, ToolUseBlock
from .image import Image


class StreamingLogger:
    """Logger that appends messages incrementally to a single file per step.

    Designed for use with think(on_message=...) so that tool call messages
    are logged to stdout and files as they are generated, not batched at the end.
    """

    def __init__(self):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._run_dir = os.path.join("logs", timestamp)
        os.makedirs(self._run_dir, exist_ok=True)
        self._step = 0
        self._step_dir: Optional[str] = None
        self._log_file = None

    @property
    def step_directory(self) -> str:
        if not self._step_dir:
            self._step_dir = os.path.join(self._run_dir, str(self._step))
            os.makedirs(self._step_dir, exist_ok=True)
        return self._step_dir

    def next_step(self):
        """Start a new step. Closes previous log file, creates new step directory and log file."""
        if self._log_file:
            self._log_file.close()
        self._step_dir = os.path.join(self._run_dir, str(self._step))
        os.makedirs(self._step_dir, exist_ok=True)
        self._log_file = open(os.path.join(self._step_dir, "log.txt"), "w")
        self._step += 1

    def log_message(self, message: Message):
        """Append a single message to the current step's log file and print to stdout."""
        formatted = self._format_message(message)

        # Save images
        for item in message.content:
            if isinstance(item, Image):
                image_bytes = base64.b64decode(item.data)
                with open(os.path.join(self._step_dir, f"image_{item.id}.jpg"), "wb") as f:
                    f.write(image_bytes)
            elif isinstance(item, ToolResult):
                for c in item.content:
                    if isinstance(c, Image):
                        image_bytes = base64.b64decode(c.data)
                        with open(os.path.join(self._step_dir, f"image_{c.id}.jpg"), "wb") as f:
                            f.write(image_bytes)

        # Write to file and flush
        if self._log_file:
            self._log_file.write(formatted + "\n\n")
            self._log_file.flush()

        # Print to stdout
        step_num = self._step - 1
        header = f"[ {message.role.upper()} — step {step_num} ]"
        print(f"\n{header}\n{'-' * len(header)}\n{formatted}")

    def close(self):
        if self._log_file:
            self._log_file.close()
            self._log_file = None

    @staticmethod
    def _format_message(message: Message) -> str:
        content_parts = []
        for item in message.content:
            if isinstance(item, str):
                content_parts.append(item)
            elif isinstance(item, Image):
                content_parts.append(f"<image_{item.id}.jpg>")
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
