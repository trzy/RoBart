from dataclasses import dataclass, field
from enum import Enum
from typing import Awaitable, Callable, List, Literal, Optional

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


@dataclass
class ThinkingBlock:
    """Represents a thinking block from Claude's response. Stored in Message.content
    for logging purposes only — not round-tripped to the API."""
    text: str


class Message:
    def __init__(self, role: Literal["user", "assistant"], content: list):
        """content: list of str | Image | ToolUseBlock | ToolResult | ThinkingBlock"""
        self.role = role
        self.content = content


class ThinkingEffort(Enum):
    NONE = "none"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    XHIGH = "xhigh"
    MAX = "max"


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
    properties: Optional[list["ToolParameter"]] = None  # fields when type is OBJECT or ARRAY of objects
    array_type: Optional["ParamType"] = None             # element type when type is ARRAY

    def __post_init__(self):
        if self.type == ParamType.ARRAY:
            if self.array_type is None:
                raise ValueError(f"ToolParameter '{self.name}': array_type is required when type is ARRAY")
            if self.array_type == ParamType.OBJECT and not self.properties:
                raise ValueError(f"ToolParameter '{self.name}': properties is required when array_type is OBJECT")
            if self.array_type != ParamType.OBJECT and self.properties:
                raise ValueError(f"ToolParameter '{self.name}': properties should not be set when array_type is {self.array_type.value}")
        elif self.type == ParamType.OBJECT:
            if not self.properties:
                raise ValueError(f"ToolParameter '{self.name}': properties is required when type is OBJECT")
            if self.array_type is not None:
                raise ValueError(f"ToolParameter '{self.name}': array_type should not be set when type is OBJECT")
        else:
            if self.properties is not None:
                raise ValueError(f"ToolParameter '{self.name}': properties should not be set for type {self.type.value}")
            if self.array_type is not None:
                raise ValueError(f"ToolParameter '{self.name}': array_type should not be set for type {self.type.value}")


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
    rewrite_history: Optional[Callable[[List[Message]], Awaitable[List[Message]]]] = None


@dataclass
class ThinkResult:
    """Return value of think().

    succeeded:True if successful, otherwise an error occurred (with text
              containing the message and messages empty).
    text:     All text blocks from Claude's responses concatenated (joined by
              newlines). Tool use blocks, tool results, and images are stripped
              out — this is purely what Claude "said" across all turns.
    messages: All Messages generated during the call, in order. If tools were
              called, this includes intermediate assistant (with ToolUseBlock)
              and user (with ToolResult) messages. Append these to your
              conversation history to preserve tool call context.
    """
    succeeded: bool
    text: str
    messages: list[Message] = field(default_factory=list)


def _param_to_schema(p: ToolParameter) -> dict:
    """Convert a ToolParameter to a JSON Schema dict."""
    schema = {"type": p.type.value, "description": p.description}
    if p.type == ParamType.OBJECT:
        obj_props = {}
        obj_required = []
        for child in p.properties:
            obj_props[child.name] = _param_to_schema(child)
            if child.required:
                obj_required.append(child.name)
        schema["properties"] = obj_props
        schema["required"] = obj_required
    elif p.type == ParamType.ARRAY:
        if p.array_type == ParamType.OBJECT:
            items_props = {}
            items_required = []
            for child in p.properties:
                items_props[child.name] = _param_to_schema(child)
                if child.required:
                    items_required.append(child.name)
            schema["items"] = {"type": "object", "properties": items_props, "required": items_required}
        else:
            schema["items"] = {"type": p.array_type.value}
    return schema


def _tool_to_api_schema(tool: Tool) -> dict:
    """Convert a Tool to the Anthropic API tool definition format."""
    properties = {}
    required = []
    for p in tool.parameters:
        properties[p.name] = _param_to_schema(p)
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


async def count_tokens(
    messages: List[Message],
    system: str,
    model: str = "claude-opus-4-6",
    tools: List[Tool] = [],
) -> int:
    """Estimate the number of input tokens for a set of messages."""
    client = anthropic.AsyncAnthropic()
    api_messages = [{"role": m.role, "content": _serialize_content_items(m.content)} for m in messages]
    kwargs = dict(model=model, system=system, messages=api_messages)
    if tools:
        kwargs["tools"] = [_tool_to_api_schema(t) for t in tools]
    response = await client.messages.count_tokens(**kwargs)
    return response.input_tokens


async def context_window_size(model: str = "claude-opus-4-6") -> Optional[int]:
    """Return the context window size (max input tokens) for the given model, or None on failure."""
    try:
        client = anthropic.AsyncAnthropic()
        response = await client.models.retrieve(model_id=model)
        return response.max_input_tokens
    except Exception as e:
        print(f"Error retrieving model info: {e}")
        return None


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
            blocks.append({"type": "text", "text": f"\nimage_{item.id}:\n"})
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
    thinking: ThinkingEffort = ThinkingEffort.NONE,
    stop_sequences: List[str] = [],
    tools: List[Tool] = [],
    on_message: Optional[Callable[[Message, List[Message]], None]] = None,
) -> ThinkResult:
    client = anthropic.AsyncAnthropic()

    # Maintain full message history as Message objects (source of truth)
    all_messages = list(messages)
    num_input_messages = len(all_messages)

    # Build tool definitions for the API
    api_tools = [_tool_to_api_schema(t) for t in tools]
    handlers = {t.name: t.handler for t in tools}
    rewriters = {t.name: t.rewrite_history for t in tools if t.rewrite_history}

    def _rebuild_api_messages():
        return [{"role": m.role, "content": _serialize_content_items(m.content)} for m in all_messages]

    try:
        accumulated_text = []
        api_messages = _rebuild_api_messages()

        while True:
            kwargs = dict(
                model=model,
                max_tokens=16384 if thinking != ThinkingEffort.NONE else 4096,
                system=system,
                messages=api_messages,
            )
            if thinking != ThinkingEffort.NONE:
                kwargs["thinking"] = {"type": "adaptive"}
                kwargs["output_config"] = {"effort": thinking.value}
            if stop_sequences:
                kwargs["stop_sequences"] = stop_sequences
            if api_tools:
                kwargs["tools"] = api_tools

            response = await client.messages.create(**kwargs)

            # Build assistant Message content from response blocks
            assistant_content = []
            tool_use_blocks = []
            for block in response.content:
                if block.type == "thinking":
                    assistant_content.append(ThinkingBlock(text=block.thinking))
                elif block.type == "text":
                    accumulated_text.append(block.text)
                    assistant_content.append(block.text)
                elif block.type == "tool_use":
                    tu = ToolUseBlock(id=block.id, name=block.name, input=block.input)
                    tool_use_blocks.append(tu)
                    assistant_content.append(tu)

            assistant_msg = Message(role="assistant", content=assistant_content)
            all_messages.append(assistant_msg)
            api_messages.append({"role": "assistant", "content": _serialize_content_items(assistant_content)})
            if on_message:
                on_message(assistant_msg, all_messages)

            if response.stop_reason != "tool_use" or not tool_use_blocks:
                break

            # Execute tool handlers and build tool_result user message
            user_content = []
            needs_rebuild = False
            for tu in tool_use_blocks:
                handler = handlers.get(tu.name)
                if handler:
                    result_content = await handler(tu.input)
                    user_content.append(ToolResult(tool_use_id=tu.id, content=result_content))
                    if tu.name in rewriters:
                        needs_rebuild = True
                else:
                    user_content.append(ToolResult(
                        tool_use_id=tu.id,
                        content=[f"Error: unknown tool '{tu.name}'"],
                        is_error=True,
                    ))

            user_msg = Message(role="user", content=user_content)
            all_messages.append(user_msg)
            if on_message:
                on_message(user_msg, all_messages)

            # Let tools rewrite history if needed, then rebuild api_messages
            if needs_rebuild:
                for tu in tool_use_blocks:
                    rewriter = rewriters.get(tu.name)
                    if rewriter:
                        all_messages = await rewriter(all_messages)
            api_messages = _rebuild_api_messages()

        text = "\n".join(accumulated_text)
        # Truncate at stop sequences just in case the model includes them in its output
        for stop in stop_sequences:
            if stop in text:
                text = text[:text.index(stop)]
        new_messages = all_messages[num_input_messages:]
        return ThinkResult(succeeded=True, text=text, messages=new_messages)
    except Exception as e:
        return ThinkResult(succeeded=False, text=f"Error: {e}", messages=[])
