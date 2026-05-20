"""
Text-prompted image segmentation using Meta's Segment Anything Model 3 (SAM 3).

Quick start:
    from server.brain.segmentation import segment

    masks = segment(pil_image, "red barrel")
    for m in masks:
        print(m.score, m.box, m.mask.shape)

macOS / Apple Silicon notes:
    SAM 3's reference implementation has a hard Triton (CUDA-only) dependency. The
    HuggingFace Transformers port works on M-series Macs (image inference is fully
    supported) provided you install Transformers from main:

        pip install --upgrade "git+https://github.com/huggingface/transformers" torchvision pillow

    Unimplemented MPS ops fall through to CPU automatically (we set
    PYTORCH_ENABLE_MPS_FALLBACK=1 on module import).
"""

import colorsys
import io
import os
from dataclasses import dataclass
from typing import List, Optional, Tuple, Union

# Must be set before any MPS op runs. Safe to set even if torch is already imported.
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

import numpy as np
import torch
from PIL import Image as PILImage
from transformers import Sam3Model, Sam3Processor


_MODEL_ID = "facebook/sam3"

_model: Optional[Sam3Model] = None
_processor: Optional[Sam3Processor] = None
_device: Optional[torch.device] = None


@dataclass
class SegmentationMask:
    """One detected instance.

    mask:  Binary mask of shape (H, W) matching the original image. True = object.
    score: Confidence in [0, 1].
    box:   Bounding box (x0, y0, x1, y1) in absolute pixel coordinates.
    """
    mask: np.ndarray
    score: float
    box: Tuple[float, float, float, float]


def _pick_device() -> torch.device:
    if torch.cuda.is_available():
        return torch.device("cuda")
    mps = getattr(torch.backends, "mps", None)
    if mps is not None and mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def _ensure_loaded() -> None:
    global _model, _processor, _device
    if _model is not None:
        return
    _device = _pick_device()
    _processor = Sam3Processor.from_pretrained(_MODEL_ID)
    _model = Sam3Model.from_pretrained(_MODEL_ID).to(_device)
    _model.eval()


def _to_pil(image: Union[PILImage.Image, bytes, bytearray, str]) -> PILImage.Image:
    if isinstance(image, PILImage.Image):
        return image.convert("RGB")
    if isinstance(image, (bytes, bytearray)):
        return PILImage.open(io.BytesIO(bytes(image))).convert("RGB")
    if isinstance(image, str):
        return PILImage.open(image).convert("RGB")
    raise TypeError(f"Unsupported image type: {type(image).__name__}")


def segment(
    image: Union[PILImage.Image, bytes, bytearray, str],
    query: str,
    threshold: float = 0.5,
    mask_threshold: float = 0.5,
) -> List[SegmentationMask]:
    """Run SAM 3 text-prompted segmentation on an image.

    Args:
        image:          A PIL Image, raw JPEG/PNG bytes, or a path on disk.
        query:          Short open-vocabulary noun phrase (e.g. "chair", "red barrel",
                        "person wearing a hat"). Use one concept per call.
        threshold:      Minimum confidence score per detected instance.
        mask_threshold: Per-pixel cutoff applied to predicted soft masks.

    Returns:
        A list of SegmentationMask sorted by descending confidence. Empty if nothing
        matched.
    """
    _ensure_loaded()
    assert _model is not None and _processor is not None and _device is not None

    pil = _to_pil(image)

    inputs = _processor(images=pil, text=query, return_tensors="pt").to(_device)
    with torch.no_grad():
        outputs = _model(**inputs)

    original_sizes = inputs.get("original_sizes")
    if original_sizes is not None:
        target_sizes = original_sizes.tolist() if hasattr(original_sizes, "tolist") else list(original_sizes)
    else:
        target_sizes = [(pil.height, pil.width)]

    results = _processor.post_process_instance_segmentation(
        outputs,
        threshold=threshold,
        mask_threshold=mask_threshold,
        target_sizes=target_sizes,
    )[0]

    masks = results["masks"]
    scores = results["scores"]
    boxes = results["boxes"]

    out: List[SegmentationMask] = []
    for i in range(len(scores)):
        mask_np = masks[i].detach().to("cpu").numpy().astype(bool)
        score = float(scores[i].detach().to("cpu").item())
        box = tuple(float(v) for v in boxes[i].detach().to("cpu").tolist())
        out.append(SegmentationMask(mask=mask_np, score=score, box=box))

    out.sort(key=lambda r: r.score, reverse=True)
    return out


def render_masks(
    masks: List[SegmentationMask],
    image: Union[PILImage.Image, bytes, bytearray, str],
    output_path: str,
    alpha: float = 0.5,
) -> None:
    """Render masks as translucent colored overlays on the image and save to disk.

    Each mask gets a distinct color (evenly spaced hues). Overlapping regions are
    painted in mask order (later masks on top).

    Args:
        masks:       Masks to draw. Each mask.mask must be (H, W) matching the image.
        image:       PIL Image, raw JPEG/PNG bytes, or a path on disk.
        output_path: Where to write the result. Format inferred from extension.
        alpha:       Overlay opacity in [0, 1].
    """
    pil = _to_pil(image)
    arr = np.array(pil.convert("RGB"), dtype=np.float32)
    h, w = arr.shape[:2]

    n = len(masks)
    for i, m in enumerate(masks):
        if m.mask.shape != (h, w):
            raise ValueError(f"mask {i} shape {m.mask.shape} does not match image ({h}, {w})")
        hue = (i / max(n, 1)) % 1.0
        r, g, b = colorsys.hsv_to_rgb(hue, 0.85, 1.0)
        color = np.array([r * 255, g * 255, b * 255], dtype=np.float32)
        arr[m.mask] = arr[m.mask] * (1.0 - alpha) + color * alpha

    out = PILImage.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB")
    out.save(output_path)
