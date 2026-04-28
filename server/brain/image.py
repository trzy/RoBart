import base64
import io
from typing import List, Literal

from PIL import Image as PILImage, ImageDraw, ImageFont

from ..messages import AnnotatedImage, AnnotatedPoint, VectorXZ


####################################################################################################
# Image
#
# Represents an image to be sent to Claude, with a stable unique ID used for logging.
####################################################################################################

class Image:
    _next_id: int = 1

    def __init__(self, data: str, media_type: Literal["image/png", "image/jpeg"], points: List[AnnotatedPoint] = None, position: VectorXZ = None, forward: VectorXZ = None):
        self.id = Image._next_id
        Image._next_id += 1
        self.data = data
        self.media_type = media_type
        self.points: List[AnnotatedPoint] = points or []
        self.position: VectorXZ = position
        self.forward: VectorXZ = forward

    @property
    def size(self) -> tuple[int, int]:
        """Return (width, height) in pixels."""
        img = PILImage.open(io.BytesIO(base64.b64decode(self.data)))
        return img.size

    def resize(self, width: int = None, height: int = None, scale: float = None) -> "Image":
        """Return a new Image at the requested size.

        Provide scale to resize both axes proportionally, or width/height (either or both).
        If only one of width/height is given, the other is derived from the aspect ratio.
        """
        img = PILImage.open(io.BytesIO(base64.b64decode(self.data))).convert("RGB")
        orig_w, orig_h = img.size

        if scale is not None:
            new_w = round(orig_w * scale)
            new_h = round(orig_h * scale)
        elif width is not None and height is not None:
            new_w, new_h = width, height
        elif width is not None:
            new_w = width
            new_h = round(orig_h * width / orig_w)
        elif height is not None:
            new_w = round(orig_w * height / orig_h)
            new_h = height
        else:
            return self

        img = img.resize((new_w, new_h), PILImage.LANCZOS)
        out = io.BytesIO()
        img.save(out, format="JPEG")
        return Image(data=base64.b64encode(out.getvalue()).decode("utf-8"), media_type="image/jpeg", points=self.points, position=self.position, forward=self.forward)


####################################################################################################
# Annotation
#
# Draws point annotations onto images as black filled boxes with a white ID number inside.
# Box dimensions are derived from font_size and padding, auto-sizing to fit any number of digits.
####################################################################################################

def _annotate_jpeg(
    jpeg_bytes: bytes,
    points: List[AnnotatedPoint],
    coords: bool = False,
    font_size: int = 16,
    padding: int = 4,
) -> bytes:
    """Draw labelled black squares onto a JPEG image and return the annotated JPEG bytes.

    Args:
        jpeg_bytes: Source image as JPEG bytes.
        points:     Points to annotate, each with an id and (x, y) pixel coordinates.
        coords:     If True, label each point with its world (x,z) coords instead of its id.
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
        label = f"{point.worldPosition.x:.1f},{point.worldPosition.z:.1f}" if coords else str(point.id)
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


def decode_annotated_image(annotated_image: AnnotatedImage, coords: bool = False) -> Image:
    """Decode an AnnotatedImage from the robot, apply point annotations, and return an Image."""
    jpeg_bytes = base64.b64decode(annotated_image.imageJpegBase64)
    annotated_bytes = _annotate_jpeg(jpeg_bytes, annotated_image.points, coords=coords)
    return Image(data=base64.b64encode(annotated_bytes).decode("utf-8"), media_type="image/jpeg", points=annotated_image.points, position=annotated_image.cameraPosition, forward=annotated_image.cameraForward)


####################################################################################################
# Load from Disk
####################################################################################################

def load_image(path: str) -> tuple[str, Literal["image/png", "image/jpeg"]]:
    """Load an image file and return (base64_data, media_type).

    Only JPEG and PNG files are supported. Raises ValueError for other formats.
    """
    ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
    media_type_map = {
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
    }
    media_type = media_type_map.get(ext)
    if media_type is None:
        raise ValueError(f"Unsupported image format '.{ext}': only JPEG and PNG are supported")
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode("utf-8")
    return data, media_type

def pil_to_base64_png(image: PILImage):
    buffered = io.BytesIO()
    # Specify the format (PNG, JPEG, etc.)
    image.save(buffered, format="PNG")
    # Encode the bytes from the buffer
    img_bytes = base64.b64encode(buffered.getvalue())
    # Convert bytes to string
    return img_bytes.decode('utf-8')