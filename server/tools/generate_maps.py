import math
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

from PIL import Image, ImageDraw, ImageFont

from ..messages import VectorXZ


class Map:
    def __init__(self, origin: VectorXZ, cell_size: float, cells_wide: int, cells_deep: int,
                 robot_position: VectorXZ = VectorXZ(x=0.0, z=0.0),
                 robot_forward: VectorXZ = VectorXZ(x=1.0, z=-1.0),
                 landmark_coordinates: Optional[Dict[int, VectorXZ]] = None):
        """Create a map from grid parameters. All cells start as '0' (unvisited).

        Args:
            origin:               World position of the top-left corner of cell (0,0).
            cell_size:            Size of each cell in world units.
            cells_wide:           Number of columns.
            cells_deep:           Number of rows.
            robot_position:       World position of the robot.
            robot_forward:        Direction vector the robot is facing.
            landmark_coordinates: Landmark ID -> world position.
        """
        self.origin = origin
        self.cell_size = cell_size
        self.cells_wide = cells_wide
        self.cells_deep = cells_deep
        self.map: List[List[str]] = [["0"] * cells_wide for _ in range(cells_deep)]
        self.robot_position = robot_position
        self.robot_forward = robot_forward
        self.landmark_coordinates = landmark_coordinates or {}

    @classmethod
    def from_strings(cls, rows: List[str], cell_size: float = 1.0, origin: VectorXZ = VectorXZ(x=0.0, z=0.0),
                     robot_forward: VectorXZ = VectorXZ(x=1.0, z=-1.0),
                     landmark_coordinates: Optional[Dict[int, VectorXZ]] = None) -> "Map":
        """Create a map from an array of strings (e.g., "001110").

        If an 'x' is present, it marks the robot's initial cell. It is replaced
        with '1' (visited) and the robot position is set to the center of that cell.
        """
        cells_deep = len(rows)
        cells_wide = len(rows[0]) if cells_deep > 0 else 0

        # Find robot 'x', replace with '1', compute position
        robot_position = VectorXZ(x=origin.x + 0.5 * cell_size, z=origin.z + 0.5 * cell_size)
        parsed = []
        for r, row in enumerate(rows):
            row_list = list(row)
            for c, ch in enumerate(row_list):
                if ch == "x":
                    row_list[c] = "1"
                    robot_position = VectorXZ(x=origin.x + (c + 0.5) * cell_size,
                                              z=origin.z + (r + 0.5) * cell_size)
            parsed.append(row_list)

        m = cls(origin=origin, cell_size=cell_size,
                cells_wide=cells_wide, cells_deep=cells_deep,
                robot_position=robot_position, robot_forward=robot_forward,
                landmark_coordinates=landmark_coordinates)
        m.map = parsed
        return m

    @staticmethod
    def _parse_cell_key(key: str) -> Tuple[int, int]:
        """Parse a cell key like 'b9' or 'B9' into (col, row) zero-indexed."""
        col_letter = ""
        row_str = ""
        for ch in key:
            if ch.isalpha():
                col_letter += ch
            else:
                row_str += ch
        col = ord(col_letter.lower()) - ord("a")
        row = int(row_str) - 1
        return col, row

    def cell_key(self, col: int, row: int) -> str:
        """Return the cell key string for a (col, row) pair."""
        return f"{chr(ord('a') + col)}{row + 1}"

    def world_to_cell(self, x: float, z: float) -> Optional[str]:
        """Return the cell key for a world position, or None if outside the grid."""
        col = int((x - self.origin.x) / self.cell_size)
        row = int((z - self.origin.z) / self.cell_size)
        if 0 <= col < self.cells_wide and 0 <= row < self.cells_deep:
            return self.cell_key(col, row)
        return None

    def point_in_cell(self, x: float, z: float, cell_key: str) -> bool:
        """Test whether a world point (x, z) is within the specified cell."""
        col, row = self._parse_cell_key(cell_key)
        cell_x = self.origin.x + col * self.cell_size
        cell_z = self.origin.z + row * self.cell_size
        return (cell_x <= x < cell_x + self.cell_size and
                cell_z <= z < cell_z + self.cell_size)

    def get(self, col: int, row: int) -> str:
        return self.map[row][col]

    def set(self, col: int, row: int, value: str):
        self.map[row][col] = value

    def __str__(self):
        return "\n".join([ f"[ {''.join(row)} ]" for row in self.map ])

@dataclass
class MapImageConfig:
    image_width: int = 1024
    occupied_color: Tuple[int, int, int] = (211, 211, 211)
    free_color: Tuple[int, int, int] = (255, 255, 255)
    grid_color: Tuple[int, int, int] = (100, 100, 100)
    label_color: Tuple[int, int, int] = (0, 0, 0)
    background_color: Tuple[int, int, int] = (255, 255, 255)
    grid_thickness: int = 1
    free_label: str = "Unexplored"
    occupied_label: str = "Visited"
    robot_color: Tuple[int, int, int] = (50, 100, 220)
    robot_label: str = "Robot"
    robot_size: float = 0.5  # proportion of cell size
    robot_line_width: int = 6
    landmark_font_color: Tuple[int, int, int] = (255, 255, 255)
    landmark_box_color: Tuple[int, int, int] = (0, 0, 0)
    landmark_padding: int = 2


def generate_images(maps: List[Map], config: MapImageConfig = MapImageConfig(), save_to_disk: bool = True) -> List[Image.Image]:
    images = []
    for i, m in enumerate(maps):
        rows = m.cells_deep
        cols = m.cells_wide

        cell_size = config.image_width // (cols + 1)
        margin = cell_size
        grid_w = cell_size * cols
        grid_h = cell_size * rows
        image_height = margin + grid_h + margin

        img = Image.new("RGB", (config.image_width, image_height), config.background_color)
        draw = ImageDraw.Draw(img)

        ox = margin
        oy = margin

        # Fill cells
        for r in range(rows):
            for c in range(cols):
                x0 = ox + c * cell_size
                y0 = oy + r * cell_size
                color = config.occupied_color if m.map[r][c] == "1" else config.free_color
                draw.rectangle([x0, y0, x0 + cell_size, y0 + cell_size], fill=color)

        # Draw grid lines
        for c in range(cols + 1):
            x = ox + c * cell_size
            draw.line([(x, oy), (x, oy + grid_h)], fill=config.grid_color, width=config.grid_thickness)
        for r in range(rows + 1):
            y = oy + r * cell_size
            draw.line([(ox, y), (ox + grid_w, y)], fill=config.grid_color, width=config.grid_thickness)

        # Draw robot chevron at world position
        robot_px = ox + (m.robot_position.x - m.origin.x) / m.cell_size * cell_size
        robot_py = oy + (m.robot_position.z - m.origin.z) / m.cell_size * cell_size
        _draw_chevron(draw, robot_px, robot_py, (m.robot_forward.x, m.robot_forward.z), cell_size * config.robot_size / 2, config.robot_color, config.robot_line_width)

        # Draw landmarks
        landmark_font_size = max(8, cell_size // 4)
        try:
            landmark_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", landmark_font_size)
        except (OSError, IOError):
            landmark_font = ImageFont.load_default()
        pad = config.landmark_padding
        pixels_per_unit = cell_size / m.cell_size
        for landmark_id, pos in m.landmark_coordinates.items():
            label = str(landmark_id)
            bbox = landmark_font.getbbox(label)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            box_w = tw + 2 * pad
            box_h = th + 2 * pad

            # Convert world position to pixel position
            px = ox + (pos.x - m.origin.x) * pixels_per_unit
            py = oy + (pos.z - m.origin.z) * pixels_per_unit

            bx0 = px - box_w / 2
            by0 = py - box_h / 2
            draw.rectangle([bx0, by0, bx0 + box_w, by0 + box_h], fill=config.landmark_box_color)
            draw.text((bx0 + pad - bbox[0], by0 + pad - bbox[1]), label, fill=config.landmark_font_color, font=landmark_font)

        # Fit font to margin
        font_size = max(8, margin * 2 // 3)
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except (OSError, IOError):
            font = ImageFont.load_default()

        # Column labels (letters)
        for c in range(cols):
            label = chr(ord("A") + c) if c < 26 else str(c)
            cx = ox + c * cell_size + cell_size // 2
            bbox = font.getbbox(label)
            lw = bbox[2] - bbox[0]
            lh = bbox[3] - bbox[1]
            draw.text((cx - lw // 2, (oy - lh) // 2), label, fill=config.label_color, font=font)

        # Row labels (numbers)
        for r in range(rows):
            label = str(r + 1)
            cy = oy + r * cell_size + cell_size // 2
            bbox = font.getbbox(label)
            lw = bbox[2] - bbox[0]
            lh = bbox[3] - bbox[1]
            draw.text(((ox - lw) // 2, cy - lh // 2), label, fill=config.label_color, font=font)

        # Legend
        legend_y = oy + grid_h + (margin - font_size) // 2
        swatch_size = font_size
        legend_entries = [
            (config.free_color, config.free_label),
            (config.occupied_color, config.occupied_label),
        ]
        legend_font_size = max(8, font_size * 3 // 4)
        try:
            legend_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", legend_font_size)
        except (OSError, IOError):
            legend_font = ImageFont.load_default()

        # Robot legend entry: chevron + label
        robot_bbox = legend_font.getbbox(config.robot_label)
        robot_entry_w = swatch_size + 4 + (robot_bbox[2] - robot_bbox[0])

        # Compute total legend width to center it
        spacing = swatch_size
        entry_widths = []
        for color, label in legend_entries:
            bbox = legend_font.getbbox(label)
            entry_widths.append(swatch_size + 4 + (bbox[2] - bbox[0]))
        total_legend_w = sum(entry_widths) + robot_entry_w + spacing * len(legend_entries)
        lx = ox + (grid_w - total_legend_w) // 2

        for (color, label), ew in zip(legend_entries, entry_widths):
            draw.rectangle([lx, legend_y, lx + swatch_size, legend_y + swatch_size], fill=color, outline=config.grid_color)
            bbox = legend_font.getbbox(label)
            lh = bbox[3] - bbox[1]
            draw.text((lx + swatch_size + 4, legend_y + (swatch_size - lh) // 2), label, fill=config.label_color, font=legend_font)
            lx += ew + spacing

        # Robot: draw chevron then label
        legend_cx = lx + swatch_size / 2
        legend_cy = legend_y + swatch_size / 2
        _draw_chevron(draw, legend_cx, legend_cy, (0, -1), swatch_size * 0.4, config.robot_color, config.robot_line_width)
        lh = robot_bbox[3] - robot_bbox[1]
        draw.text((lx + swatch_size + 4, legend_y + (swatch_size - lh) // 2), config.robot_label, fill=config.label_color, font=legend_font)

        if save_to_disk:
            filename = f"map_{i}.png"
            img.save(filename)
            print(f"Saved {filename}")
        images.append(img)

    return images


def _draw_chevron(draw: ImageDraw.Draw, cx: float, cy: float, forward: Tuple[float, float], radius: float, color: Tuple[int, int, int], width: int):
    """Draw a chevron (V shape) pointing in the forward direction.

    The chevron tip is at the front (in the forward direction), and the two
    arms extend backward at 45 degrees to each side.

    Args:
        cx, cy:   Center of the chevron in pixel coordinates.
        forward:  (x, z) direction vector. z negative = up on screen.
        radius:   Half-size of the chevron (distance from center to tip/arms).
        color:    Line color.
        width:    Line width.
    """
    fx, fz = forward
    length = math.sqrt(fx * fx + fz * fz)
    if length < 1e-9:
        return
    # Normalize: forward direction in pixel space (z maps to y on screen)
    dx = fx / length
    dy = fz / length

    # Tip: center + forward * radius
    tip = (cx + dx * radius, cy + dy * radius)

    # Two arms extend backward and to each side
    # Perpendicular vector
    px, py = -dy, dx

    back_x = cx - dx * radius
    back_y = cy - dy * radius
    left = (back_x + px * radius, back_y + py * radius)
    right = (back_x - px * radius, back_y - py * radius)

    # Draw two lines: left arm -> tip, tip -> right arm
    draw.line([left, tip], fill=color, width=width)
    draw.line([tip, right], fill=color, width=width)


map_0 = Map.from_strings(
    rows=[
        "0000000000",
        "00000x0000",
        "0001110000",
        "0001000000",
    ],
    landmark_coordinates={
        0: VectorXZ(x=4.3, z=2.7),
        7: VectorXZ(x=4.8, z=2.3),
        1: VectorXZ(x=3.5, z=3.5),
    }
)

map_1 = Map.from_strings(
    rows=[
        "0000000000",
        "000001x000",
        "0001110000",
        "0000000000",
    ],
)

if __name__ == "__main__":
    maps = [
        map_0
    ]

    generate_images(maps)
