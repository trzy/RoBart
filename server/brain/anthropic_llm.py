from typing import Callable, List, Optional

import anthropic

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


def _tool_to_api_schema(tool: Tool) -> dict:
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


def _serialize_content_items(items: list) -> list[dict]:
    """Convert internal content items to Anthropic API content blocks."""
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


async def count_tokens(
    messages: List[Message],
    system: str,
    model: str,
    tools: List[Tool] = [],
) -> int:
    client = anthropic.AsyncAnthropic()
    api_messages = [{"role": m.role, "content": _serialize_content_items(m.content)} for m in messages]
    kwargs = dict(model=model, system=system, messages=api_messages)
    if tools:
        kwargs["tools"] = [_tool_to_api_schema(t) for t in tools]
    response = await client.messages.count_tokens(**kwargs)
    return response.input_tokens


async def context_window_size(model: str) -> Optional[int]:
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


async def think(
    messages: List[Message],
    system: str,
    model: str,
    thinking: ThinkingEffort,
    stop_sequences: List[str],
    tools: List[Tool],
    on_message: Optional[Callable[[Message, List[Message]], None]],
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
