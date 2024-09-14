#
# navigation.py
# Bart Trzynadlowski
#
# Navigation UI.
#

import asyncio
from typing import Awaitable, Callable, Optional

from pydantic import BaseModel
import tkinter as tk
from tkinter import ttk

from .messages import RequestOccupancyMapMessage, OccupancyMapMessage, DrivePathMessage


CELL_SIZE = 10
DEGREE_SIGN = u"\N{DEGREE SIGN}"

class MapWindow:
    def __init__(self, occupancy_map: OccupancyMapMessage, send_message: Callable[[BaseModel,], Awaitable[None]]):
        self._send_message = send_message
        self._map = occupancy_map
        self._path = []

        self._root = tk.Tk()
        self._root.title("Occupancy Map")

        self._canvas = tk.Canvas(self._root, width=self._map.cellsWide * CELL_SIZE, height=self._map.cellsDeep * CELL_SIZE)
        self._canvas.pack()

        style = ttk.Style()
        style.configure('TButton', foreground='black', background='lightgray')

        self._refresh_button = ttk.Button(self._root, text="Refresh", command=self._refresh_map, style="TButton")
        self._refresh_button.pack(side=tk.LEFT, padx=5, pady=5)

        self._clear_button = ttk.Button(self._root, text="Reset Path", command=self._clear_path, style="TButton")
        self._clear_button.pack(side=tk.LEFT, padx=5, pady=5)

        self._360_button = ttk.Button(self._root, text=f"360{DEGREE_SIGN}", command=self._scan_360, style="TButton")
        self._360_button.pack(side=tk.LEFT, padx=5, pady=5)
        
        self._go_button = ttk.Button(self._root, text="Go", command=self._go, style="TButton")
        self._go_button.pack(side=tk.LEFT, padx=5, pady=5)
        
        self._canvas.bind("<Button-1>", self._on_click)

        self._is_running = True
        self._root.protocol("WM_DELETE_WINDOW", self._on_closed)
        
        self._draw_map()

    def show(self):
        if self._root is not None:
            self._root.deiconify()

    def hide(self):
        if self._root is not None:
            self._root.withdraw()

    def update(self):
        if self._root is not None:
            self._root.update()

    def destroy(self):
        if self._root is not None:
            self._root.destroy()
            self._root = None

    def _on_closed(self):
        self.destroy()

    def _draw_map(self):
        if self._root is None:
            return

        self._canvas.delete("all")
        for z in range(self._map.cellsDeep):
            for x in range(self._map.cellsWide):
                if self._map.occupancy[z * self._map.cellsWide + x] != 0:
                    self._canvas.create_rectangle(
                        x * CELL_SIZE, z * CELL_SIZE,
                        (x + 1) * CELL_SIZE, (z + 1) * CELL_SIZE,
                        fill="blue", outline=""
                    )
        
        for i in range(len(self._path) - 1):
            x1, z1 = self._path[i]
            x2, z2 = self._path[i + 1]
            self._canvas.create_line(
                x1 * CELL_SIZE + CELL_SIZE // 2,
                z1 * CELL_SIZE + CELL_SIZE // 2,
                x2 * CELL_SIZE + CELL_SIZE // 2,
                z2 * CELL_SIZE + CELL_SIZE // 2,
                fill="red", width=2
            )
        
        for x, z in self._path:
            self._canvas.create_rectangle(
                x * CELL_SIZE, z * CELL_SIZE,
                (x + 1) * CELL_SIZE, (z + 1) * CELL_SIZE,
                fill="black", outline=""
            )

        # Draw robot
        robot_x = self._map.robotCell[0]
        robot_z = self._map.robotCell[1]
        self._canvas.create_oval(
            robot_x * CELL_SIZE, robot_z * CELL_SIZE,
            (robot_x + 1) * CELL_SIZE, (robot_z + 1) * CELL_SIZE,
            fill="red", outline=""
        )
            
    def _on_click(self, event):
        x = event.x // CELL_SIZE
        z = event.y // CELL_SIZE
        if len(self._path) == 0:
            # Path must begin with robot
            robot_x = self._map.robotCell[0]
            robot_z = self._map.robotCell[1]
            self._path.append((robot_x, robot_z))
        self._path.append((x, z))
        self._draw_map()
    
    def _refresh_map(self):
        msg = RequestOccupancyMapMessage()
        asyncio.ensure_future(self._send_message(msg))
        print("Requested occupancy map refresh")

    def _clear_path(self):
        self._path = []
        self._draw_map()
    
    def _go(self):
        msg = DrivePathMessage(pathCells=[[x, z] for x, z in self._path])
        asyncio.ensure_future(self._send_message(msg))
        print("Sent path")

    def _scan_360(self):
        msg = DrivePathMessage(pathCells=[])
        asyncio.ensure_future(self._send_message(msg))
        print("Sent 360 scan command")

class NavigationUI:
    _visible: asyncio.Event
    _send_message: Callable[[BaseModel,], Awaitable[None]] = lambda msg: None
    _window: Optional[MapWindow]

    def __init__(self):
        self._visible = asyncio.Event()
        self._window = None
    
    async def run(self, send_message: Callable[[BaseModel,], Awaitable[None]]):
        self._send_message = send_message
        while True:
            # Wait until visible, then show if window exists
            await self._visible.wait()
            self._window.show()

            # While visible, update
            while self._visible.is_set():
                self._window.update()
                await asyncio.sleep(0.01)
            
            # Hide
            self._window.hide()
    
    def show(self, occupancy_map: Optional[OccupancyMapMessage]):
        if occupancy_map is not None:
            # Destroy existing window and create a new one for this occupancy map
            self._destroy_window()
            self._create_window(occupancy_map=occupancy_map)
            self._visible.set()
        else:
            # Hide
            self._visible.clear()
        
    def _create_window(self, occupancy_map: OccupancyMapMessage):
        self._window = MapWindow(occupancy_map=occupancy_map, send_message=self._send_message)

    def _destroy_window(self):
        if self._window is not None:
            self._window.destroy()
            self._window = None
