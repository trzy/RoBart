from dataclasses import dataclass
from typing import List


@dataclass
class Block:
    tag: str
    content: str


def parse_blocks(text: str) -> List[Block]:
    """
    Extracts blocks delimited by markup tags from text. Only top-level tags are considered.

    For example, the text below:
        <block1>
            <block1a></block1a>
        </block1>
        <block2>hello</block2>

    Would result in blocks: block1, block2.

    Tags consist of only alphanumeric characters and underscores. If a block has no closing tag,
    it is still returned with whatever contents were accumulated.
    """
    result: List[Block] = []
    i = 0
    inside_block = False
    current_tag = ""
    current_contents = ""

    def is_valid_tag_char(ch: str) -> bool:
        return ch.isalnum() or ch == "_"

    while i < len(text):
        ch = text[i]

        if not inside_block and ch == "<":
            # Potential opening tag
            j = i + 1
            potential_tag = ""
            while j < len(text) and text[j] != ">":
                if is_valid_tag_char(text[j]):
                    potential_tag += text[j]
                    j += 1
                else:
                    break
            if j < len(text) and text[j] == ">" and potential_tag:
                inside_block = True
                current_tag = potential_tag
                current_contents = ""
                i = j + 1
                continue
        elif inside_block:
            closing = f"</{current_tag}>"
            if text[i:i + len(closing)] == closing:
                result.append(Block(tag=current_tag, content=current_contents))
                inside_block = False
                i += len(closing)
                continue
            else:
                current_contents += ch

        i += 1

    # Unterminated block — include it anyway
    if inside_block:
        result.append(Block(tag=current_tag, content=current_contents))

    return result
