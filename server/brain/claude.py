from dataclasses import dataclass, field
from enum import Enum
from typing import Awaitable, Callable, List, Literal

import anthropic

from .image import Image


@dataclass
class ToolUseBlock:
    """Represents a tool_use block from Claude's response. Stored in Message.content
    so that tool call history is preserved across think() calls."""
    id: str
    name: str
    input: dict


@dataclass
class ToolResult:
    """Represents a tool_result block sent back to Claude. Stored in Message.content
    so that tool call history is preserved across think() calls."""
    tool_use_id: str
    content: list  # list[str | Image]
    is_error: bool = False


class Message:
    def __init__(self, role: Literal["user", "assistant"], content: list):
        """content: list of str | Image | ToolUseBlock | ToolResult"""
        self.role = role
        self.content = content


class ParamType(Enum):
    STRING = "string"
    INTEGER = "integer"
    NUMBER = "number"
    BOOLEAN = "boolean"
    ARRAY = "array"
    OBJECT = "object"


@dataclass
class ToolParameter:
    name: str
    type: ParamType
    description: str
    required: bool = True


@dataclass
class Tool:
    """A tool that Claude can call during a think() invocation.

    Example usage:
        async def get_weather(params: dict) -> list[str | Image]:
            city = params["city"]
            return [f"Weather in {city}: 72°F, sunny"]

        weather_tool = Tool(
            name="get_weather",
            description="Get the current weather for a city.",
            parameters=[
                ToolParameter(name="city", type=ParamType.STRING, description="City name"),
            ],
            handler=get_weather,
        )

        result = await think(messages=..., system=..., tools=[weather_tool])
        # result.text contains the final text
        # result.messages contains all messages generated (append to history)
    """
    name: str
    description: str
    parameters: list[ToolParameter]
    handler: Callable[[dict], Awaitable[list[str | Image]]]


@dataclass
class ThinkResult:
    """Return value of think().

    text:     All text blocks from Claude's responses concatenated (joined by
              newlines). Tool use blocks, tool results, and images are stripped
              out — this is purely what Claude "said" across all turns.
    messages: All Messages generated during the call, in order. If tools were
              called, this includes intermediate assistant (with ToolUseBlock)
              and user (with ToolResult) messages. Append these to your
              conversation history to preserve tool call context.
    """
    text: str
    messages: list[Message] = field(default_factory=list)


def _tool_to_api_schema(tool: Tool) -> dict:
    """Convert a Tool to the Anthropic API tool definition format."""
    properties = {}
    required = []
    for p in tool.parameters:
        properties[p.name] = {"type": p.type.value, "description": p.description}
        if p.required:
            required.append(p.name)
    return {
        "name": tool.name,
        "description": tool.description,
        "input_schema": {
            "type": "object",
            "properties": properties,
            "required": required,
        },
    }


async def list_models() -> List[str]:
    try:
        client = anthropic.AsyncAnthropic()
        response = await client.models.list()
        return [m.id for m in response.data]
    except Exception as e:
        print(f"Error: {e}")
    return []


def _serialize_content_items(items: list) -> list[dict]:
    """Convert a list of str/Image/ToolUseBlock/ToolResult items to Anthropic API content blocks."""
    blocks = []
    for item in items:
        if isinstance(item, str):
            blocks.append({"type": "text", "text": item})
        elif isinstance(item, Image):
            coords = ""
            if item.position:
                coords += f" pos=({item.position.x},{item.position.z})"
            if item.forward:
                coords += f" fwd=({item.forward.x},{item.forward.z})"
            blocks.append({"type": "text", "text": f"image_{item.id}{coords}"})
            blocks.append({
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": item.media_type,
                    "data": item.data,
                },
            })
        elif isinstance(item, ToolUseBlock):
            blocks.append({
                "type": "tool_use",
                "id": item.id,
                "name": item.name,
                "input": item.input,
            })
        elif isinstance(item, ToolResult):
            result_block = {
                "type": "tool_result",
                "tool_use_id": item.tool_use_id,
                "content": _serialize_content_items(item.content),
            }
            if item.is_error:
                result_block["is_error"] = True
            blocks.append(result_block)
    return blocks


async def think(
    messages: List[Message],
    system: str,
    model: str = "claude-opus-4-6",
    stop_sequences: List[str] = [],
    tools: List[Tool] = [],
) -> ThinkResult:
    client = anthropic.AsyncAnthropic()

    # Convert caller's Message objects to API format
    api_messages = []
    for message in messages:
        api_messages.append({"role": message.role, "content": _serialize_content_items(message.content)})

    # Build tool definitions for the API
    api_tools = [_tool_to_api_schema(t) for t in tools]
    handlers = {t.name: t.handler for t in tools}

    try:
        accumulated_text = []
        new_messages = []

        while True:
            kwargs = dict(
                model=model,
                max_tokens=4096,
                system=system,
                messages=api_messages,
            )
            if stop_sequences:
                kwargs["stop_sequences"] = stop_sequences
            if api_tools:
                kwargs["tools"] = api_tools

            response = await client.messages.create(**kwargs)

            # Build assistant Message content from response blocks
            assistant_content = []
            tool_use_blocks = []
            for block in response.content:
                if block.type == "text":
                    accumulated_text.append(block.text)
                    assistant_content.append(block.text)
                elif block.type == "tool_use":
                    tu = ToolUseBlock(id=block.id, name=block.name, input=block.input)
                    tool_use_blocks.append(tu)
                    assistant_content.append(tu)

            assistant_msg = Message(role="assistant", content=assistant_content)
            new_messages.append(assistant_msg)
            api_messages.append({"role": "assistant", "content": _serialize_content_items(assistant_content)})

            if response.stop_reason != "tool_use" or not tool_use_blocks:
                break

            # Execute tool handlers and build tool_result user message
            user_content = []
            for tu in tool_use_blocks:
                handler = handlers.get(tu.name)
                if handler:
                    result_content = await handler(tu.input)
                    user_content.append(ToolResult(tool_use_id=tu.id, content=result_content))
                else:
                    user_content.append(ToolResult(
                        tool_use_id=tu.id,
                        content=[f"Error: unknown tool '{tu.name}'"],
                        is_error=True,
                    ))

            user_msg = Message(role="user", content=user_content)
            new_messages.append(user_msg)
            api_messages.append({"role": "user", "content": _serialize_content_items(user_content)})

        text = "\n".join(accumulated_text)
        # Truncate at stop sequences just in case the model includes them in its output
        for stop in stop_sequences:
            if stop in text:
                text = text[:text.index(stop)]
        return ThinkResult(text=text, messages=new_messages)
    except Exception as e:
        return ThinkResult(text=f"Error: {e}", messages=[])
