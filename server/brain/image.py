import base64
import io
from typing import List, Literal

from PIL import Image as PILImage, ImageDraw, ImageFont

from ..messages import AnnotatedImage, AnnotatedPoint


####################################################################################################
# Image
#
# Represents an image to be sent to Claude, with a stable unique ID used for logging.
####################################################################################################

class Image:
    _next_id: int = 1

    def __init__(self, data: str, media_type: Literal["image/png", "image/jpeg"]):
        self.id = Image._next_id
        Image._next_id += 1
        self.data = data
        self.media_type = media_type


####################################################################################################
# Annotation
#
# Draws point annotations onto images as black filled boxes with a white ID number inside.
# Box dimensions are derived from font_size and padding, auto-sizing to fit any number of digits.
####################################################################################################

def _annotate_jpeg(
    jpeg_bytes: bytes,
    points: List[AnnotatedPoint],
    font_size: int = 16,
    padding: int = 4,
) -> bytes:
    """Draw labelled black squares onto a JPEG image and return the annotated JPEG bytes.

    Args:
        jpeg_bytes: Source image as JPEG bytes.
        points:     Points to annotate, each with an id and (x, y) pixel coordinates.
        font_size:  Font height in pixels. Box height = font_size + 2 * padding.
        padding:    Pixels of space between the text and each edge of the box.
    """
    img = PILImage.open(io.BytesIO(jpeg_bytes)).convert("RGB")
    draw = ImageDraw.Draw(img)

    try:
        font = ImageFont.load_default(size=font_size)
    except TypeError:
        # Pillow < 10.1.0 — load_default() takes no size argument
        font = ImageFont.load_default()

    for point in points:
        label = str(point.id)
        l, t, r, b = draw.textbbox((0, 0), label, font=font)
        text_w, text_h = r - l, b - t

        box_w = text_w + 2 * padding
        box_h = text_h + 2 * padding

        # Unity screen coordinates have origin at bottom-left; flip Y to image coordinates
        x = point.screenX
        y = img.height - point.screenY

        bx0 = x - box_w / 2
        by0 = y - box_h / 2
        bx1 = bx0 + box_w
        by1 = by0 + box_h

        draw.rectangle([bx0, by0, bx1, by1], fill="black")
        draw.text((bx0 + padding - l, by0 + padding - t), label, fill="white", font=font)

    out = io.BytesIO()
    img.save(out, format="JPEG")
    return out.getvalue()


def decode_annotated_image(annotated_image: AnnotatedImage) -> Image:
    """Decode an AnnotatedImage from the robot, apply point annotations, and return an Image."""
    jpeg_bytes = base64.b64decode(annotated_image.imageJpegBase64)
    annotated_bytes = _annotate_jpeg(jpeg_bytes, annotated_image.points)
    return Image(data=base64.b64encode(annotated_bytes).decode("utf-8"), media_type="image/jpeg")
