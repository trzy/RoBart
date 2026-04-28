import random
from dataclasses import dataclass
from typing import Dict, List, Tuple

from PIL import Image, ImageDraw, ImageFont


@dataclass
class Map:
    map: List[str]
    landmarks_by_cell: Dict[str, List[int]]

    def __str__(self):
        return "\n".join([ f"[ {row} ]" for row in self.map ])

@dataclass
class MapImageConfig:
    image_width: int = 1024
    occupied_color: Tuple[int, int, int] = (211, 211, 211)
    free_color: Tuple[int, int, int] = (255, 255, 255)
    grid_color: Tuple[int, int, int] = (100, 100, 100)
    label_color: Tuple[int, int, int] = (0, 0, 0)
    background_color: Tuple[int, int, int] = (255, 255, 255)
    grid_thickness: int = 1
    margin: int = 32
    legend_height: int = 40
    free_label: str = "Unexplored"
    occupied_label: str = "Visited"
    robot_color: Tuple[int, int, int] = (50, 100, 220)
    robot_label: str = "Robot"
    landmark_font_color: Tuple[int, int, int] = (255, 255, 255)
    landmark_box_color: Tuple[int, int, int] = (0, 0, 0)
    landmark_padding: int = 2


def generate_images(maps: List[Map], config: MapImageConfig = MapImageConfig(), save_to_disk: bool = True) -> List[Image.Image]:
    images = []
    for i, m in enumerate(maps):
        rows = len(m.map)
        cols = len(m.map[0]) if rows > 0 else 0

        cell_size = (config.image_width - config.margin) // cols
        grid_w = cell_size * cols
        grid_h = cell_size * rows
        image_height = config.margin + grid_h + config.legend_height

        img = Image.new("RGB", (config.image_width, image_height), config.background_color)
        draw = ImageDraw.Draw(img)

        ox = config.margin
        oy = config.margin

        # Fill cells
        robot_cells = []
        for r in range(rows):
            for c in range(cols):
                x0 = ox + c * cell_size
                y0 = oy + r * cell_size
                ch = m.map[r][c]
                if ch == "x":
                    draw.rectangle([x0, y0, x0 + cell_size, y0 + cell_size], fill=config.occupied_color)
                    robot_cells.append((x0, y0))
                elif ch == "1":
                    draw.rectangle([x0, y0, x0 + cell_size, y0 + cell_size], fill=config.occupied_color)
                else:
                    draw.rectangle([x0, y0, x0 + cell_size, y0 + cell_size], fill=config.free_color)

        # Draw grid lines
        for c in range(cols + 1):
            x = ox + c * cell_size
            draw.line([(x, oy), (x, oy + grid_h)], fill=config.grid_color, width=config.grid_thickness)
        for r in range(rows + 1):
            y = oy + r * cell_size
            draw.line([(ox, y), (ox + grid_w, y)], fill=config.grid_color, width=config.grid_thickness)

        # Draw X marks on robot cells
        x_pad = cell_size // 4
        x_width = max(2, config.grid_thickness + 1)
        for x0, y0 in robot_cells:
            draw.line([(x0 + x_pad, y0 + x_pad), (x0 + cell_size - x_pad, y0 + cell_size - x_pad)], fill=config.robot_color, width=x_width)
            draw.line([(x0 + cell_size - x_pad, y0 + x_pad), (x0 + x_pad, y0 + cell_size - x_pad)], fill=config.robot_color, width=x_width)

        # Draw landmarks
        landmark_font_size = max(8, cell_size // 4)
        try:
            landmark_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", landmark_font_size)
        except (OSError, IOError):
            landmark_font = ImageFont.load_default()
        pad = config.landmark_padding
        rng = random.Random(42)
        for cell_key, ids in m.landmarks_by_cell.items():
            col_letter = ""
            row_str = ""
            for ch in cell_key:
                if ch.isalpha():
                    col_letter += ch
                else:
                    row_str += ch
            c = ord(col_letter.lower()) - ord("a")
            r = int(row_str) - 1
            cell_x0 = ox + c * cell_size
            cell_y0 = oy + r * cell_size

            for landmark_id in ids:
                label = str(landmark_id)
                bbox = landmark_font.getbbox(label)
                tw = bbox[2] - bbox[0]
                th = bbox[3] - bbox[1]
                box_w = tw + 2 * pad
                box_h = th + 2 * pad

                # Random center point within the cell, clamped so the box stays inside
                cx = rng.randint(cell_x0 + box_w // 2 + 1, cell_x0 + cell_size - box_w // 2 - 1)
                cy = rng.randint(cell_y0 + box_h // 2 + 1, cell_y0 + cell_size - box_h // 2 - 1)

                bx0 = cx - box_w // 2
                by0 = cy - box_h // 2
                draw.rectangle([bx0, by0, bx0 + box_w, by0 + box_h], fill=config.landmark_box_color)
                draw.text((bx0 + pad - bbox[0], by0 + pad - bbox[1]), label, fill=config.landmark_font_color, font=landmark_font)

        # Fit font to cell size
        font_size = max(8, cell_size * 2 // 3)
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
        legend_y = oy + grid_h + (config.legend_height - font_size) // 2
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

        # Robot legend entry: just the X mark + label
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

        # Robot: draw X mark then label
        sp = swatch_size // 4
        draw.line([(lx + sp, legend_y + sp), (lx + swatch_size - sp, legend_y + swatch_size - sp)], fill=config.robot_color, width=x_width)
        draw.line([(lx + swatch_size - sp, legend_y + sp), (lx + sp, legend_y + swatch_size - sp)], fill=config.robot_color, width=x_width)
        lh = robot_bbox[3] - robot_bbox[1]
        draw.text((lx + swatch_size + 4, legend_y + (swatch_size - lh) // 2), config.robot_label, fill=config.label_color, font=legend_font)

        if save_to_disk:
            filename = f"map_{i}.png"
            img.save(filename)
            print("Saved {filename}")
        images.append(img)

    return images


map_0 = Map(
    map=[
        "0000000000",
        "00000x0000",
        "0001110000",
        "0001000000",
    ],
    landmarks_by_cell={
        "e3": [ 0, 7 ],
        "d4": [ 1 ],
    }
)

map_1 = Map(
    map=[
        "0000000000",
        "000001x000",
        "0001110000",
        "0000000000",
    ],
    landmarks_by_cell={}
)

if __name__ == "__main__":
    maps = [
        map_0
    ]

    generate_images(maps)
