from typing import List, Literal

import anthropic

from .image import Image


class Message:
    def __init__(self, role: Literal["user", "assistant"], content: List[str | Image]):
        self.role = role
        self.content = content


async def list_models() -> List[str]:
    try:
        client = anthropic.AsyncAnthropic()
        response = await client.models.list()
        return [m.id for m in response.data]
    except Exception as e:
        print(f"Error: {e}")
    return []

async def think(messages: List[Message], system: str, model: str = "claude-opus-4-6", stop_sequences: List[str] = []) -> str:
    client = anthropic.AsyncAnthropic()

    api_messages = []
    for message in messages:
        content_blocks = []
        for item in message.content:
            if isinstance(item, str):
                content_blocks.append({"type": "text", "text": item})
            elif isinstance(item, Image):
                content_blocks.append({
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": item.media_type,
                        "data": item.data,
                    },
                })
        api_messages.append({"role": message.role, "content": content_blocks})

    try:
        kwargs = dict(
            model=model,
            max_tokens=4096,
            system=system,
            messages=api_messages,
        )
        if stop_sequences:
            kwargs["stop_sequences"] = stop_sequences
        response = await client.messages.create(**kwargs)
        text = response.content[0].text
        # Truncate at stop sequences just in case the model includes them in its output
        for stop in stop_sequences:
            if stop in text:
                text = text[:text.index(stop)]
        return text
    except Exception as e:
        return f"Error: {e}"
