import json
from typing import Callable, List, Optional

import openai
import tiktoken

from .image import Image
from .llm import (
    Message,
    ParamType,
    ThinkResult,
    ThinkingBlock,
    ThinkingEffort,
    Tool,
    ToolParameter,
    ToolResult,
    ToolUseBlock,
    _param_to_schema,
)


# Hardcoded context-window sizes for current OpenAI models. Used as a fast path;
# unknown variants (including dated suffixes like "gpt-5.4-2026-03-05") fall through
# to the prefix-based resolution in context_window_size().
_CONTEXT_WINDOWS = {
    "gpt-4o": 128_000,
    "gpt-4o-mini": 128_000,
    "gpt-4.1": 1_047_576,
    "gpt-4.1-mini": 1_047_576,
    "gpt-4.1-nano": 1_047_576,
    "gpt-5": 400_000,
    "gpt-5-mini": 400_000,
    "gpt-5-nano": 400_000,
    "gpt-5-codex": 400_000,
    "gpt-5-pro": 400_000,
    "gpt-5.1": 400_000,
    "gpt-5.2": 400_000,
    "gpt-5.2-pro": 400_000,
    "gpt-5.3": 400_000,
    "gpt-5.4": 1_050_000,
    "gpt-5.4-mini": 1_050_000,
    "gpt-5.4-nano": 1_050_000,
    "gpt-5.4-pro": 1_050_000,
    "gpt-5.5": 1_000_000,
    "gpt-5.5-pro": 1_000_000,
    "o1": 200_000,
    "o1-mini": 128_000,
    "o1-pro": 200_000,
    "o3": 200_000,
    "o3-mini": 200_000,
    "o3-pro": 200_000,
    "o4-mini": 200_000,
}

# Conservative fallback when no prefix matches.
_DEFAULT_CONTEXT_WINDOW = 128_000

# Fallback estimate for image tokens (Responses API actual is model-dependent).
_IMAGE_TOKEN_ESTIMATE = 1500


def _is_reasoning_model(model: str) -> bool:
    return model.startswith(("o1", "o3", "o4", "gpt-5"))


def _thinking_effort_to_openai(effort: ThinkingEffort) -> Optional[str]:
    return {
        ThinkingEffort.LOW: "low",
        ThinkingEffort.MEDIUM: "medium",
        ThinkingEffort.HIGH: "high",
        ThinkingEffort.XHIGH: "high",
        ThinkingEffort.MAX: "high",
    }.get(effort)


def _tool_to_api_schema(tool: Tool) -> dict:
    properties = {}
    required = []
    for p in tool.parameters:
        properties[p.name] = _param_to_schema(p)
        if p.required:
            required.append(p.name)
    return {
        "type": "function",
        "name": tool.name,
        "description": tool.description,
        "parameters": {
            "type": "object",
            "properties": properties,
            "required": required,
        },
    }


def _image_data_url(image: Image) -> str:
    return f"data:{image.media_type};base64,{image.data}"


def _serialize_user_content(items: list) -> list[dict]:
    """Build a content list for an input_message item from str/Image entries."""
    blocks = []
    for item in items:
        if isinstance(item, str):
            blocks.append({"type": "input_text", "text": item})
        elif isinstance(item, Image):
            coords = ""
            if image_pos := getattr(item, "position", None):
                coords += f" pos=({image_pos.x},{image_pos.z})"
            if image_fwd := getattr(item, "forward", None):
                coords += f" fwd=({image_fwd.x},{image_fwd.z})"
            blocks.append({"type": "input_text", "text": f"\nimage_{item.id}:\n"})
            blocks.append({"type": "input_image", "image_url": _image_data_url(item)})
    return blocks


def _serialize_messages_to_input(messages: List[Message]) -> list[dict]:
    """Convert internal Messages to the flat list of input items the Responses API expects.

    A single internal Message can produce multiple top-level items because OpenAI separates
    function_call / function_call_output from message items.
    """
    items: list[dict] = []
    for m in messages:
        if m.role == "user":
            # Separate ToolResult items from user text/images
            text_image_items = [c for c in m.content if isinstance(c, (str, Image))]
            tool_results = [c for c in m.content if isinstance(c, ToolResult)]

            if text_image_items:
                items.append({
                    "type": "message",
                    "role": "user",
                    "content": _serialize_user_content(text_image_items),
                })

            for tr in tool_results:
                inner_text_only = all(isinstance(c, str) for c in tr.content)
                if inner_text_only:
                    output = "".join(c for c in tr.content)
                else:
                    output = _serialize_user_content(tr.content)
                items.append({
                    "type": "function_call_output",
                    "call_id": tr.tool_use_id,
                    "output": output,
                })
        else:  # assistant
            text_chunks = [c for c in m.content if isinstance(c, str)]
            if text_chunks:
                items.append({
                    "type": "message",
                    "role": "assistant",
                    "content": [{"type": "output_text", "text": t} for t in text_chunks],
                })
            for c in m.content:
                if isinstance(c, ToolUseBlock):
                    items.append({
                        "type": "function_call",
                        "call_id": c.id,
                        "name": c.name,
                        "arguments": json.dumps(c.input),
                    })
                # ThinkingBlock is stripped (not round-tripped)
    return items


def _get_encoding(model: str):
    try:
        return tiktoken.encoding_for_model(model)
    except KeyError:
        return tiktoken.get_encoding("o200k_base")


async def count_tokens(
    messages: List[Message],
    system: str,
    model: str,
    tools: List[Tool] = [],
) -> int:
    enc = _get_encoding(model)
    total = 0
    if system:
        total += len(enc.encode(system))
    for t in tools:
        total += len(enc.encode(json.dumps(_tool_to_api_schema(t))))
    for m in messages:
        total += 4  # rough per-message overhead
        for item in m.content:
            if isinstance(item, str):
                total += len(enc.encode(item))
            elif isinstance(item, Image):
                total += _IMAGE_TOKEN_ESTIMATE
            elif isinstance(item, ToolUseBlock):
                total += len(enc.encode(item.name))
                total += len(enc.encode(json.dumps(item.input)))
            elif isinstance(item, ToolResult):
                for inner in item.content:
                    if isinstance(inner, str):
                        total += len(enc.encode(inner))
                    elif isinstance(inner, Image):
                        total += _IMAGE_TOKEN_ESTIMATE
            # ThinkingBlock is stripped
    return total


async def context_window_size(model: str) -> Optional[int]:
    if model in _CONTEXT_WINDOWS:
        return _CONTEXT_WINDOWS[model]
    # Strip a trailing dated suffix like "-2026-03-05" and retry exact match.
    base = model.rsplit("-", 3)[0] if model.count("-") >= 3 else model
    if base in _CONTEXT_WINDOWS:
        return _CONTEXT_WINDOWS[base]
    # Family-level fallbacks for unrecognized variants.
    if model.startswith(("gpt-5.4", "gpt-5.5")):
        return 1_000_000
    if model.startswith("gpt-5"):
        return 400_000
    if model.startswith("gpt-4.1"):
        return 1_047_576
    if model.startswith("gpt-4"):
        return 128_000
    if model.startswith(("o1", "o3", "o4")):
        return 200_000
    return _DEFAULT_CONTEXT_WINDOW


async def list_models() -> List[str]:
    try:
        client = openai.AsyncOpenAI()
        response = await client.models.list()
        return [m.id for m in response.data]
    except Exception as e:
        print(f"Error: {e}")
    return []


async def think(
    messages: List[Message],
    system: str,
    model: str,
    thinking: ThinkingEffort,
    stop_sequences: List[str],
    tools: List[Tool],
    on_message: Optional[Callable[[Message, List[Message]], None]],
) -> ThinkResult:
    client = openai.AsyncOpenAI()

    all_messages = list(messages)
    num_input_messages = len(all_messages)

    api_tools = [_tool_to_api_schema(t) for t in tools]
    handlers = {t.name: t.handler for t in tools}
    rewriters = {t.name: t.rewrite_history for t in tools if t.rewrite_history}

    reasoning_effort = _thinking_effort_to_openai(thinking) if thinking != ThinkingEffort.NONE else None
    use_reasoning = reasoning_effort is not None and _is_reasoning_model(model)

    try:
        accumulated_text: List[str] = []

        while True:
            input_items = _serialize_messages_to_input(all_messages)

            kwargs = dict(
                model=model,
                instructions=system,
                input=input_items,
                max_output_tokens=16384 if thinking != ThinkingEffort.NONE else 4096,
            )
            if use_reasoning:
                kwargs["reasoning"] = {"effort": reasoning_effort}
            if api_tools:
                kwargs["tools"] = api_tools
            if stop_sequences:
                # Responses API doesn't natively support stop sequences for all models;
                # we still truncate on the client side below.
                pass

            response = await client.responses.create(**kwargs)

            # Build assistant Message content from response output items
            assistant_content = []
            tool_use_blocks: List[ToolUseBlock] = []
            for item in response.output:
                item_type = getattr(item, "type", None)
                if item_type == "message":
                    for c in getattr(item, "content", []) or []:
                        c_type = getattr(c, "type", None)
                        if c_type == "output_text":
                            assistant_content.append(c.text)
                            accumulated_text.append(c.text)
                elif item_type == "function_call":
                    try:
                        parsed_args = json.loads(item.arguments) if item.arguments else {}
                    except json.JSONDecodeError:
                        parsed_args = {}
                    tu = ToolUseBlock(id=item.call_id, name=item.name, input=parsed_args)
                    tool_use_blocks.append(tu)
                    assistant_content.append(tu)
                elif item_type == "reasoning":
                    summary_parts = []
                    for s in getattr(item, "summary", []) or []:
                        text = getattr(s, "text", None)
                        if text:
                            summary_parts.append(text)
                    if summary_parts:
                        assistant_content.append(ThinkingBlock(text="\n".join(summary_parts)))

            assistant_msg = Message(role="assistant", content=assistant_content)
            all_messages.append(assistant_msg)
            if on_message:
                on_message(assistant_msg, all_messages)

            if not tool_use_blocks:
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

            if needs_rebuild:
                for tu in tool_use_blocks:
                    rewriter = rewriters.get(tu.name)
                    if rewriter:
                        all_messages = await rewriter(all_messages)

        text = "\n".join(accumulated_text)
        for stop in stop_sequences:
            if stop in text:
                text = text[:text.index(stop)]
        new_messages = all_messages[num_input_messages:]
        return ThinkResult(succeeded=True, text=text, messages=new_messages)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return ThinkResult(succeeded=False, text=f"Error: {e}", messages=[])
