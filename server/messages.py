#
# messages.py
# Bart Trzynadlowski
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
# Messages passed between iOS client and Python server. Must be kept in sync with their iOS counter-
# parts.
#

from typing import Dict, List

from pydantic import BaseModel


class HelloMessage(BaseModel):
   message: str

class LogMessage(BaseModel):
    text: str

class DriveForDurationMessage(BaseModel):
    reverse: bool
    seconds: float
    speed: float

class DriveForDistanceMessage(BaseModel):
    reverse: bool
    meters: float
    speed: float

class RotateMessage(BaseModel):
    degrees: float

class DriveForwardMessage(BaseModel):
    deltaMeters: float

class WatchdogSettingsMessage(BaseModel):
    enabled: bool
    timeoutSeconds: float

class PWMSettingsMessage(BaseModel):
    pwmFrequency: int

class ThrottleMessage(BaseModel):
    maxThrottle: float

class PIDGainsMessage(BaseModel):
    whichPID: str
    Kp: float
    Ki: float
    Kd: float

class HoverboardRTTMeasurementMessage(BaseModel):
    numSamples: int
    delay: float
    rttSeconds: List[float]

class AngularVelocityMeasurementMessage(BaseModel):
    steering: float
    numSeconds: float
    angularVelocityResult: float

class PositionGoalToleranceMessage(BaseModel):
    positionGoalTolerance: float

class RenderSceneGeometryMessage(BaseModel):
    planes: bool
    meshes: bool

class RequestOccupancyMapMessage(BaseModel):
    pass

class OccupancyMapMessage(BaseModel):
    cellsWide: int
    cellsDeep: int
    occupancy: List[float]
    robotCell: List[int]        # 2 elements: cellX, cellZ
    pathCells: List[List[int]]  # list of [cellX, cellZ]

class DrivePathMessage(BaseModel):
    pathCells: List[List[int]]  # list of [cellX, cellZ]
    pathFinding: bool

class RequestAnnotatedViewMessage(BaseModel):
    pass

class AnnotatedViewMessage(BaseModel):
    imageBase64: str

class AIStepMessage(BaseModel):
    timestamp: str
    stepNumber: int
    modelInput: str
    modelOutput: str
    imagesBase64: Dict[str, str]