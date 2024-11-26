#
# image_viewer.py
# Bart Trzynadlowski, 2024
#
# This file is part of RoBart.
#
# RoBart is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# RoBart is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with RoBart. If not, see <http://www.gnu.org/licenses/>.
#

#
# Image viewer window.
#

import asyncio
from io import BytesIO
from typing import Tuple

from PIL import Image, ImageTk
import tkinter as tk


class ImageViewer:
    _visible: asyncio.Event

    def __init__(self):
        self._visible = asyncio.Event()
        self._image: ImageTk.PhotoImage | None = None
        self._image_size: Tuple[int, int] | None = None
        self._image_name: str | None = None

        self._root = tk.Tk()

        self._label = tk.Label(self._root)
        self._label.pack()

        self._root.protocol("WM_DELETE_WINDOW", self.hide)

        # Initially hidden
        self._root.withdraw()

    def hide(self):
        self._visible.clear()

    def show(self, image: bytes, name: str | None = None, width: int | None = None, height: int | None = None):
        pil_image = Image.open(BytesIO(image))
        pil_image = self._resize_image(image=pil_image, width=width, height=height)
        self._image = ImageTk.PhotoImage(image=pil_image)
        self._image_size = pil_image.size
        self._window_title = name if name is not None else "Image"
        self._visible.set()

    async def run(self):
        while True:
            # Wait until visible, then show if window exists
            await self._visible.wait()
            self._root.deiconify()

            # While visible, update
            while self._visible.is_set():
                self._label.config(image=self._image)
                self._label.image = self._image
                self._root.title(self._window_title)
                self._root.geometry(f"{self._image_size[0]}x{self._image_size[1]}")
                self._root.update()
                await asyncio.sleep(0.1)

            # Hide
            self._root.withdraw()
            self._root.update() # update to take effect

    @staticmethod
    def _resize_image(image: Image, width: int | None, height: int | None) -> Image:
        original_width, original_height = image.size
        if width is not None and height is not None:
            image = image.resize((width, height))
        elif width is not None:
            height = int((width / original_width) * original_height)
            image = image.resize((width, height))
        elif height is not None:
            width = int((height / original_height) * original_width)
            image = image.resize((width, height))
        return image