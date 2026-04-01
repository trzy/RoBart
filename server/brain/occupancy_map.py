import base64
import io
import math
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Literal, Optional, Tuple

from PIL import Image as PILImage, ImageDraw, ImageFont

from .image import Image
from ..messages import VectorXZ


class CoordUnit(Enum):
    CELLS = "cells"
    METERS = "meters"


@dataclass
class MapAnnotation:
    """An annotation to render on the occupancy map."""

    x: float = 0.0
    z: float = 0.0
    unit: CoordUnit = CoordUnit.METERS

    label: str = ""
    font_size: int = 12
    font_color: str = "white"
    box: bool = True
    box_color: str = "black"


@dataclass
class RobotMarker:
    """Draws the robot as a colored circle with a forward-direction arrow."""

    position: VectorXZ = field(default_factory=lambda: VectorXZ(x=0, z=0))
    forward: VectorXZ = field(default_factory=lambda: VectorXZ(x=0, z=0))

    radius_cells: float = 2.0
    color: str = "red"
    arrow_color: str = "red"


@dataclass
class RenderOptions:
    """All parameters for render_occupancy_map()."""

    # Grid data
    cells_wide: int = 0
    cells_deep: int = 0
    occupancy: List[int] = field(default_factory=list)      # row-major, 0 = free, 1 = occupied

    # Coordinate mapping (needed when annotations/robot use world coords)
    origin_x: float = 0.0       # world X of the cell (0,0) corner
    origin_z: float = 0.0       # world Z of the cell (0,0) corner
    cell_size: float = 1.0

    # Sizing — provide cell_pixels OR image_width (cell_pixels takes priority)
    cell_pixels: Optional[int] = None
    image_width: Optional[int] = None

    # Colors
    empty_color: str = "#404040"
    obstacle_color: str = "#2F00FF"

    # Optional visitation heatmap
    last_visited: Optional[List[float]] = None  # row-major, <0 means never visited
    heatmap_recent_color: Tuple[int, int, int] = (0, 255, 0)
    heatmap_old_color: Tuple[int, int, int] = (40, 40, 40)

    # Annotations and robot
    annotations: List[MapAnnotation] = field(default_factory=list)
    robot: Optional[RobotMarker] = None

    # If set, save the rendered image to this path
    output_path: Optional[str] = None


def render_occupancy_map(opts: RenderOptions) -> Image:
    """Render an occupancy map to an Image object."""

    cells_wide = opts.cells_wide
    cells_deep = opts.cells_deep

    # Determine pixel size per cell
    if opts.cell_pixels is not None:
        cpx = opts.cell_pixels
    elif opts.image_width is not None:
        cpx = max(1, opts.image_width // cells_wide)
    else:
        cpx = 4

    img_w = cells_wide * cpx
    img_h = cells_deep * cpx

    img = PILImage.new("RGB", (img_w, img_h))
    draw = ImageDraw.Draw(img)

    # ------------------------------------------------------------------
    # Base layer: empty vs obstacle, with optional visitation heatmap
    # ------------------------------------------------------------------
    heatmap = _compute_heatmap(opts) if opts.last_visited else None

    for z in range(cells_deep):
        for x in range(cells_wide):
            i = z * cells_wide + x
            if opts.occupancy[i]:
                color = opts.obstacle_color
            elif heatmap and heatmap[i] is not None:
                color = heatmap[i]
            else:
                color = opts.empty_color
            px = x * cpx
            py = z * cpx
            draw.rectangle([px, py, px + cpx - 1, py + cpx - 1], fill=color)

    # ------------------------------------------------------------------
    # Robot marker
    # ------------------------------------------------------------------
    if opts.robot is not None:
        _draw_robot(draw, opts.robot, opts, cpx)

    # ------------------------------------------------------------------
    # Annotations
    # ------------------------------------------------------------------
    for ann in opts.annotations:
        _draw_annotation(draw, ann, opts, cpx)

    # ------------------------------------------------------------------
    # Encode and return
    # ------------------------------------------------------------------
    if opts.output_path:
        img.save(opts.output_path)

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    data_b64 = base64.b64encode(buf.getvalue()).decode("utf-8")
    return Image(data=data_b64, media_type="image/png")


# --------------------------------------------------------------------------
# Internal helpers
# --------------------------------------------------------------------------

def _world_to_cell(wx: float, wz: float, opts: RenderOptions) -> Tuple[float, float]:
    """Convert world coordinates to fractional cell coordinates."""
    cx = (wx - opts.origin_x) / opts.cell_size
    cz = (wz - opts.origin_z) / opts.cell_size
    return cx, cz


def _cell_to_pixel_center(cx: float, cz: float, cpx: int) -> Tuple[float, float]:
    """Convert fractional cell coordinates to pixel center."""
    return (cx + 0.5) * cpx, (cz + 0.5) * cpx


def _compute_heatmap(opts: RenderOptions) -> Optional[List[Optional[Tuple[int, int, int]]]]:
    """Compute per-cell RGB colors for the visitation heatmap."""
    last_visited = opts.last_visited
    total = opts.cells_wide * opts.cells_deep

    visited_times = [t for t in last_visited if t >= 0]
    if not visited_times:
        return None

    newest = max(visited_times)
    oldest = min(visited_times)
    time_range = newest - oldest

    r0, g0, b0 = opts.heatmap_recent_color
    r1, g1, b1 = opts.heatmap_old_color

    result: List[Optional[Tuple[int, int, int]]] = [None] * total
    for i in range(total):
        t = last_visited[i]
        if t < 0:
            continue
        if time_range < 1e-6:
            frac = 0.0
        else:
            frac = (newest - t) / time_range   # 0 = newest, 1 = oldest
        r = int(r0 + (r1 - r0) * frac)
        g = int(g0 + (g1 - g0) * frac)
        b = int(b0 + (b1 - b0) * frac)
        result[i] = (r, g, b)
    return result


def _draw_robot(draw: ImageDraw.ImageDraw, robot: RobotMarker, opts: RenderOptions, cpx: int):
    cx, cz = _world_to_cell(robot.position.x, robot.position.z, opts)
    px, py = _cell_to_pixel_center(cx, cz, cpx)
    radius = robot.radius_cells * cpx

    # Circle
    draw.ellipse(
        [px - radius, py - radius, px + radius, py + radius],
        fill=robot.color,
    )

    # Arrow protruding from circle edge with triangle head
    fx, fz = robot.forward.x, robot.forward.z
    length = math.hypot(fx, fz)
    if length < 1e-6:
        return
    fx /= length
    fz /= length

    # Shaft runs from circle edge outward
    shaft_start_x = px + fx * radius
    shaft_start_y = py + fz * radius
    shaft_len = radius * 1.2
    tip_x = shaft_start_x + fx * shaft_len
    tip_y = shaft_start_y + fz * shaft_len

    arrow_width = max(2, cpx // 2)
    draw.line([(shaft_start_x, shaft_start_y), (tip_x, tip_y)], fill=robot.arrow_color, width=arrow_width)


def _draw_annotation(draw: ImageDraw.ImageDraw, ann: MapAnnotation, opts: RenderOptions, cpx: int):
    if ann.unit == CoordUnit.METERS:
        cx, cz = _world_to_cell(ann.x, ann.z, opts)
    else:
        cx, cz = ann.x, ann.z
    px, py = _cell_to_pixel_center(cx, cz, cpx)

    try:
        font = ImageFont.load_default(size=ann.font_size)
    except TypeError:
        font = ImageFont.load_default()

    if not ann.label:
        return

    l, t, r, b = draw.textbbox((0, 0), ann.label, font=font)
    text_w, text_h = r - l, b - t
    padding = 3

    tx = px - text_w / 2
    ty = py - text_h / 2

    if ann.box:
        bx0 = tx - padding
        by0 = ty - padding
        bx1 = tx + text_w + padding
        by1 = ty + text_h + padding
        draw.rectangle([bx0, by0, bx1, by1], fill=ann.box_color)

    draw.text((tx - l, ty - t), ann.label, fill=ann.font_color, font=font)
