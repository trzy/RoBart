from dataclasses import dataclass, field
from enum import Enum
from typing import Awaitable, Callable, List, Literal, Optional

from .image import Image


@dataclass
class ToolUseBlock:
    """Represents a tool-use block from a model response. Stored in Message.content
    so that tool call history is preserved across think() calls."""
    id: str
    name: str
    input: dict


@dataclass
class ToolResult:
    """Represents a tool-result block sent back to the model. Stored in Message.content
    so that tool call history is preserved across think() calls."""
    tool_use_id: str
    content: list  # list[str | Image]
    is_error: bool = False


@dataclass
class ThinkingBlock:
    """Represents a thinking/reasoning block from a model response. Stored in
    Message.content for logging purposes only — not round-tripped to the API."""
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
    """A tool that the model can call during a think() invocation.

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
    text:     All text blocks from the model's responses concatenated (joined by
              newlines). Tool use blocks, tool results, and images are stripped
              out — this is purely what the model "said" across all turns.
    messages: All Messages generated during the call, in order. If tools were
              called, this includes intermediate assistant (with ToolUseBlock)
              and user (with ToolResult) messages. Append these to your
              conversation history to preserve tool call context.
    """
    succeeded: bool
    text: str
    messages: list[Message] = field(default_factory=list)


def _param_to_schema(p: ToolParameter) -> dict:
    """Convert a ToolParameter to a JSON Schema dict. Generic — used by both backends."""
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


####################################################################################################
# Backend dispatch
####################################################################################################

_ANTHROPIC_PREFIXES = ("claude-",)
_OPENAI_PREFIXES = ("gpt-", "o1", "o3", "o4", "chatgpt-")


def _pick_backend(model: str):
    if model.startswith(_ANTHROPIC_PREFIXES):
        from . import anthropic_llm
        return anthropic_llm
    if model.startswith(_OPENAI_PREFIXES):
        from . import openai_llm
        return openai_llm
    raise ValueError(f"Unknown model: {model!r}. Expected a Claude or OpenAI model id.")


async def think(
    messages: List[Message],
    system: str,
    model: str = "claude-opus-4-7",
    thinking: ThinkingEffort = ThinkingEffort.NONE,
    stop_sequences: List[str] = [],
    tools: List[Tool] = [],
    on_message: Optional[Callable[[Message, List[Message]], None]] = None,
) -> ThinkResult:
    return await _pick_backend(model).think(
        messages=messages,
        system=system,
        model=model,
        thinking=thinking,
        stop_sequences=stop_sequences,
        tools=tools,
        on_message=on_message,
    )


async def count_tokens(
    messages: List[Message],
    system: str,
    model: str = "claude-opus-4-7",
    tools: List[Tool] = [],
) -> int:
    return await _pick_backend(model).count_tokens(
        messages=messages,
        system=system,
        model=model,
        tools=tools,
    )


async def context_window_size(model: str = "claude-opus-4-7") -> Optional[int]:
    return await _pick_backend(model).context_window_size(model=model)


async def list_models(backend: Literal["anthropic", "openai", "all"] = "all") -> List[str]:
    results: List[str] = []
    if backend in ("anthropic", "all"):
        try:
            from . import anthropic_llm
            results.extend(await anthropic_llm.list_models())
        except Exception as e:
            if backend == "anthropic":
                raise
            print(f"Warning: failed to list Anthropic models: {e}")
    if backend in ("openai", "all"):
        try:
            from . import openai_llm
            results.extend(await openai_llm.list_models())
        except Exception as e:
            if backend == "openai":
                raise
            print(f"Warning: failed to list OpenAI models: {e}")
    return results
